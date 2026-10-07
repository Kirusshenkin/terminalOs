public import Foundation
public import PhosphorCore

/// One step of a provisioning recipe.
public struct RecipeStep: Identifiable, Sendable, Equatable {
    public enum Skip: Sendable, Equatable {
        /// Already satisfied on this host: the named tool is installed.
        case alreadyInstalled(String)
        /// The step's own check passed: whatever it does is already done.
        case alreadyDone
        /// Cannot run here: no apt, so not Ubuntu or Debian.
        case needsApt
        /// Cannot run here: the commands assume Linux (systemd, sshd_config.d).
        case needsLinux
        /// Cannot run here: closing passwords with no key locks the door.
        case noKeys
        /// Cannot run here: no key was chosen for the step to work with.
        case noKeysChosen
        /// Cannot run here: the key this connection uses would be removed.
        case wouldLockOut
        /// Cannot run here: commands need root, and sudo wants a password.
        case needsRoot

        /// Cannot run here at all, as opposed to not being needed.
        public var isUnsupported: Bool {
            switch self {
            case .alreadyInstalled, .alreadyDone: false
            case .needsApt, .needsLinux, .noKeys, .noKeysChosen, .wouldLockOut, .needsRoot: true
            }
        }
    }

    /// Stable identifier; built-in steps are named in the interface by it.
    public var id: String
    /// Title written by the recipe's author. Built-in steps have none: their
    /// names come from the string tables, in the interface language.
    public var title: String?
    /// What sets this instance apart, such as the certbot domain.
    public var detail: String?
    /// Commands in order. Every one is shown before anything runs.
    public var commands: [String]
    /// Run on the host before the step; exit 0 means the work is already done.
    public var check: String?
    /// Commands run as the connecting user rather than as root. Key steps
    /// touch that user's `~/.ssh`, not root's.
    public var asUser: Bool
    /// Decides whether the step is needed on this host.
    public var skipReason: @Sendable (HostProfile) -> Skip?

    public init(
        id: String,
        title: String? = nil,
        detail: String? = nil,
        commands: [String],
        check: String? = nil,
        asUser: Bool = false,
        skipReason: @escaping @Sendable (HostProfile) -> Skip? = { _ in nil }
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.commands = commands
        self.check = check
        self.asUser = asUser
        self.skipReason = skipReason
    }

    public static func == (lhs: RecipeStep, rhs: RecipeStep) -> Bool {
        lhs.id == rhs.id && lhs.commands == rhs.commands && lhs.check == rhs.check
    }
}

/// Which systems a recipe is written for. An empty list means "any".
public struct RecipeRequirement: Sendable, Equatable, Codable {
    public var families: [HostProfile.OSFamily]
    public var packageManagers: [String]

    public init(families: [HostProfile.OSFamily] = [], packageManagers: [String] = []) {
        self.families = families
        self.packageManagers = packageManagers
    }

    public func allows(_ profile: HostProfile) -> Bool {
        if !families.isEmpty, !families.contains(profile.osFamily) { return false }
        if !packageManagers.isEmpty {
            guard let manager = profile.packageManager, packageManagers.contains(manager) else {
                return false
            }
        }
        return true
    }
}

/// An ordered list of steps, with the systems it is meant for.
public struct Recipe: Identifiable, Sendable {
    /// Where a recipe came from. A file is someone else's text: it is never
    /// run without its commands on screen first.
    public enum Origin: Sendable, Equatable {
        case builtIn
        case file
    }

    public var id: String
    public var name: String
    public var steps: [RecipeStep]
    public var requirement: RecipeRequirement
    public var origin: Origin
    /// Steps whose failure stops the run. Recipes from files stop on any
    /// failure: we cannot know which of their steps the rest depend on.
    public var mustSucceed: Set<String>

    public init(
        id: String, name: String, steps: [RecipeStep],
        requirement: RecipeRequirement = RecipeRequirement(),
        origin: Origin = .builtIn, mustSucceed: Set<String>? = nil
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.requirement = requirement
        self.origin = origin
        self.mustSucceed = mustSucceed ?? Set(steps.map(\.id))
    }

    public func applies(to profile: HostProfile) -> Bool { requirement.allows(profile) }

    /// Steps that still need doing on this host, and why the rest do not.
    public func plan(for profile: HostProfile) -> [(step: RecipeStep, skip: RecipeStep.Skip?)] {
        steps.map { step in
            if let skip = step.skipReason(profile) { return (step, skip) }
            // Без root и без sudo без пароля системные шаги не выполнить, а
            // спросить пароль посреди прогона некому.
            if !step.asUser, !profile.isRoot, !profile.canSudo { return (step, .needsRoot) }
            return (step, nil)
        }
    }
}

/// Parameters the built-in recipes ask for.
public struct RecipeInputs: Sendable, Equatable {
    public var domain: String?
    public var email: String?
    public var hostname: String?
    /// The port sshd listens on. The firewall must keep it open, or the
    /// recipe locks the person out of their own server.
    public var sshPort: Int
    /// Public key lines to authorize, as they appear in a `.pub` file.
    public var keys: [String]
    /// Remove every other key after authorizing `keys`.
    public var removeOtherKeys: Bool
    /// Whether the key this connection uses is among `keys`. Removing other
    /// keys is refused unless it is: that would cut the branch we sit on.
    public var connectionKeyKept: Bool

    public init(
        domain: String? = nil, email: String? = nil, hostname: String? = nil, sshPort: Int = 22,
        keys: [String] = [], removeOtherKeys: Bool = false, connectionKeyKept: Bool = false
    ) {
        self.domain = domain
        self.email = email
        self.hostname = hostname
        self.sshPort = sshPort
        self.keys = keys
        self.removeOtherKeys = removeOtherKeys
        self.connectionKeyKept = connectionKeyKept
    }
}

/// The recipes that ship with the app.
///
/// In the base recipe order is deliberate: passwords are closed last, once
/// everything else is proven to work, and only after a second key-based
/// connection has succeeded.
public enum BuiltInRecipe {
    /// Every built-in recipe, in the order the interface offers them.
    public static func all(_ inputs: RecipeInputs) -> [Recipe] {
        [base(inputs), dockerOnly(), keys(inputs)]
    }

    /// The recipe that gets run on every new server.
    public static func base(_ inputs: RecipeInputs) -> Recipe {
        var steps = [packages(), docker(), nginx()]
        if let certbot = certbot(inputs) { steps.append(certbot) }
        steps.append(firewall(sshPort: inputs.sshPort))
        steps.append(closePasswords())
        return Recipe(
            id: "base", name: "base", steps: steps, requirement: aptLinux,
            mustSucceed: ["packages", "docker"])
    }

    /// Docker and nothing else, for a server that only runs containers.
    public static func dockerOnly() -> Recipe {
        Recipe(id: "docker", name: "docker", steps: [packages(), docker()], requirement: aptLinux)
    }

    /// Authorizes the chosen keys and, if asked, removes every other one.
    ///
    /// Plain POSIX shell on the connecting user's `~/.ssh`, so it works on any
    /// Linux and on a Mac alike.
    public static func keys(_ inputs: RecipeInputs) -> Recipe {
        var steps = [authorizeKeys(inputs.keys)]
        if inputs.removeOtherKeys { steps.append(removeOtherKeys(inputs)) }
        return Recipe(
            id: "keys", name: "keys", steps: steps,
            requirement: RecipeRequirement(families: [.linux, .darwin]))
    }

    private static let aptLinux = RecipeRequirement(families: [.linux], packageManagers: ["apt"])

    /// Steps that require an independent key-based login before they run:
    /// both can lock the person out if keys do not actually work.
    public static let needsKeyProof: Set<String> = ["passwords", "keys.prune"]

    /// The part of a public key line that identifies the key: type and blob,
    /// without the comment the person may have edited.
    static func keyBody(_ line: String) -> String? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        let prefixes = ["ssh-", "ecdsa-", "sk-"]
        guard parts.count >= 2, prefixes.contains(where: { parts[0].hasPrefix($0) }) else { return nil }
        return "\(parts[0]) \(parts[1])"
    }

    private static func authorizeKeys(_ lines: [String]) -> RecipeStep {
        let keys = lines.compactMap { line in keyBody(line).map { (line, $0) } }
        var commands = [
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys"
                + " && chmod 600 ~/.ssh/authorized_keys"
        ]
        // Ключ уже есть — с любым комментарием — значит, второй раз его не пишем.
        for (line, body) in keys {
            commands.append(
                "grep -qF \(Shell.quote(body)) ~/.ssh/authorized_keys"
                    + " || printf '%s\\n' \(Shell.quote(line)) >> ~/.ssh/authorized_keys")
        }
        return RecipeStep(
            id: "keys.add", commands: commands, asUser: true,
            skipReason: { _ in keys.isEmpty ? .noKeysChosen : nil })
    }

    /// Keeps only the chosen keys. A dated copy of the old file stays next to
    /// it, and an empty result is never written.
    private static func removeOtherKeys(_ inputs: RecipeInputs) -> RecipeStep {
        let bodies = inputs.keys.compactMap(keyBody)
        let patterns = bodies.map { "-e \(Shell.quote($0))" }.joined(separator: " ")
        let kept = inputs.connectionKeyKept
        return RecipeStep(
            id: "keys.prune",
            commands: [
                "cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.phosphor-$(date +%Y%m%d%H%M%S)",
                "grep -F \(patterns) ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.phosphor-new"
                    + " && test -s ~/.ssh/authorized_keys.phosphor-new"
                    + " && chmod 600 ~/.ssh/authorized_keys.phosphor-new"
                    + " && mv ~/.ssh/authorized_keys.phosphor-new ~/.ssh/authorized_keys",
            ],
            asUser: true,
            skipReason: { _ in
                if bodies.isEmpty { return .noKeysChosen }
                return kept ? nil : .wouldLockOut
            })
    }

    private static func requiresApt(_ profile: HostProfile) -> RecipeStep.Skip? {
        profile.isProvisionable ? nil : .needsApt
    }

    private static func packages() -> RecipeStep {
        RecipeStep(
            id: "packages",
            commands: [
                "apt-get update -qq",
                // Каждая команда — отдельный ssh-вызов: `export` в своей строке
                // ничего бы не дал, поэтому переменная стоит у самой команды.
                "DEBIAN_FRONTEND=noninteractive apt-get -y -qq upgrade",
                "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades ca-certificates curl gnupg",
                "dpkg-reconfigure -f noninteractive unattended-upgrades",
            ],
            skipReason: requiresApt
        )
    }

    private static func docker() -> RecipeStep {
        // Подстановки должны раскрыться на сервере: в одинарных кавычках они
        // ушли бы в docker.list буквально. Дистрибутив — из os-release, а не
        // `ubuntu` для всех: у Debian свой репозиторий.
        let repository =
            "echo \"deb [arch=$(dpkg --print-architecture) "
            + "signed-by=/etc/apt/keyrings/docker.asc] "
            + "https://download.docker.com/linux/$(. /etc/os-release && echo \"$ID\") "
            + "$(. /etc/os-release && echo \"$VERSION_CODENAME\") stable\""
            + " > /etc/apt/sources.list.d/docker.list"
        // Логи контейнеров без потолка — самая частая причина внезапно
        // кончившегося диска. Ограничение не стоит ничего.
        let daemon = #"{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}"#
        return RecipeStep(
            id: "docker",
            commands: [
                "install -m 0755 -d /etc/apt/keyrings",
                "curl -fsSL \"https://download.docker.com/linux/$(. /etc/os-release && echo \"$ID\")/gpg\""
                    + " -o /etc/apt/keyrings/docker.asc",
                "chmod a+r /etc/apt/keyrings/docker.asc",
                repository,
                "apt-get update -qq",
                "apt-get install -y -qq docker-ce docker-ce-cli containerd.io"
                    + " docker-buildx-plugin docker-compose-plugin",
                "printf '%s' \(Shell.quote(daemon)) > /etc/docker/daemon.json",
                "mkdir -p /etc/systemd/journald.conf.d",
                "printf '[Journal]\\nSystemMaxUse=500M\\n'"
                    + " > /etc/systemd/journald.conf.d/phosphor.conf",
                "systemctl restart systemd-journald",
                "systemctl enable --now docker",
            ],
            skipReason: { profile in
                if let skip = requiresApt(profile) { return skip }
                return profile.dockerPath != nil ? .alreadyInstalled("docker") : nil
            }
        )
    }

    private static func nginx() -> RecipeStep {
        RecipeStep(
            id: "nginx",
            commands: ["apt-get install -y -qq nginx", "systemctl enable --now nginx"],
            skipReason: { profile in
                if let skip = requiresApt(profile) { return skip }
                return profile.hasNginx ? .alreadyInstalled("nginx") : nil
            }
        )
    }

    /// Появляется только с валидными доменом и почтой: certbot всё равно их
    /// проверит, но лучше отказать до сетевого запроса.
    private static func certbot(_ inputs: RecipeInputs) -> RecipeStep? {
        guard let domain = inputs.domain.flatMap(Validate.domain),
            let email = inputs.email.flatMap(Validate.email)
        else { return nil }
        // Спрашиваем Let's Encrypt только если имя действительно указывает сюда.
        // Стрельба вслепую сжигает лимит выпуска на неделю.
        let dnsCheck =
            "test \"$(getent hosts \(Shell.quote(domain)) | awk '{print $1}' | head -1)\""
            + " = \"$(curl -fsS --max-time 5 https://api.ipify.org)\""
            + " || { echo 'DNS домена не указывает на этот сервер'; exit 1; }"
        return RecipeStep(
            id: "certbot",
            detail: domain,
            commands: [
                "apt-get install -y -qq certbot python3-certbot-nginx",
                dnsCheck,
                "certbot --nginx --non-interactive --agree-tos"
                    + " -m \(Shell.quote(email)) -d \(Shell.quote(domain))",
            ],
            skipReason: requiresApt
        )
    }

    private static func firewall(sshPort: Int) -> RecipeStep {
        // Docker пишет правила в iptables мимо UFW, поэтому опубликованный порт
        // открыт наружу, что бы firewall ни думал. Тихо исправить это нельзя —
        // но можно показать.
        let auditPorts =
            "grep -rHnE '^[[:space:]]*-[[:space:]]*\"?[0-9]+:[0-9]+'"
            + " /srv /opt /root --include='*compose*.y*ml' 2>/dev/null"
            + " | grep -v '127\\.0\\.0\\.1'"
            + " | sed 's/^/WARNING port open outside firewall: /' || true"
        return RecipeStep(
            id: "ufw",
            commands: [
                "apt-get install -y -qq ufw",
                "ufw --force reset",
                "ufw default deny incoming",
                "ufw default allow outgoing",
                // Порт, на котором реально слушает sshd: с одним «22» сервер на
                // нестандартном порту запер бы человека снаружи.
                "ufw allow \(sshPort)/tcp comment 'ssh'",
                "ufw allow 80/tcp comment 'http'",
                "ufw allow 443/tcp comment 'https'",
                "ufw --force enable",
                auditPorts,
            ],
            skipReason: requiresApt
        )
    }

    private static func closePasswords() -> RecipeStep {
        RecipeStep(
            id: "passwords",
            commands: [
                "mkdir -p /etc/ssh/sshd_config.d",
                "printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\n"
                    + "PermitRootLogin prohibit-password\\n'"
                    + " > /etc/ssh/sshd_config.d/10-phosphor.conf",
                "sshd -t",
                "systemctl reload ssh 2>/dev/null || systemctl reload sshd",
            ],
            skipReason: { profile in
                guard profile.osFamily == .linux else { return .needsLinux }
                return profile.authorizedKeyCount > 0 ? nil : .noKeys
            }
        )
    }
}
