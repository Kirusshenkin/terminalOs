public import Foundation
public import PhosphorCore

/// One step of a provisioning recipe.
public struct RecipeStep: Identifiable, Sendable, Equatable {
    public enum Skip: Sendable, Equatable {
        /// Already satisfied on this host.
        case alreadyDone(String)
        /// Cannot run here at all.
        case unsupported(String)
    }

    public var id: String
    public var title: String
    /// Commands in order. Every one is shown before anything runs.
    public var commands: [String]
    /// Decides whether the step is needed on this host.
    public var skipReason: @Sendable (HostProfile) -> Skip?

    public init(
        id: String,
        title: String,
        commands: [String],
        skipReason: @escaping @Sendable (HostProfile) -> Skip? = { _ in nil }
    ) {
        self.id = id
        self.title = title
        self.commands = commands
        self.skipReason = skipReason
    }

    public static func == (lhs: RecipeStep, rhs: RecipeStep) -> Bool {
        lhs.id == rhs.id && lhs.commands == rhs.commands
    }
}

/// An ordered, editable list of steps.
public struct Recipe: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var steps: [RecipeStep]

    /// Steps that still need doing on this host, and why the rest do not.
    public func plan(for profile: HostProfile) -> [(step: RecipeStep, skip: RecipeStep.Skip?)] {
        steps.map { ($0, $0.skipReason(profile)) }
    }
}

/// Parameters the built-in recipe asks for.
public struct RecipeInputs: Sendable, Equatable {
    public var domain: String?
    public var email: String?
    public var hostname: String?

    public init(domain: String? = nil, email: String? = nil, hostname: String? = nil) {
        self.domain = domain
        self.email = email
        self.hostname = hostname
    }
}

/// The recipe that gets run on every new server.
///
/// Order is deliberate: passwords are closed last, once everything else is
/// proven to work, and only after a second key-based connection has succeeded.
public enum BuiltInRecipe {
    public static func base(_ inputs: RecipeInputs) -> Recipe {
        var steps = [packages(), docker(), nginx()]
        if let certbot = certbot(inputs) { steps.append(certbot) }
        steps.append(firewall())
        steps.append(closePasswords())
        return Recipe(id: "base", name: "базовый", steps: steps)
    }

    private static func requiresApt(_ profile: HostProfile) -> RecipeStep.Skip? {
        profile.isProvisionable ? nil : .unsupported("нужен apt: Ubuntu или Debian")
    }

    private static func packages() -> RecipeStep {
        RecipeStep(
            id: "packages",
            title: "обновить пакеты и unattended-upgrades",
            commands: [
                "export DEBIAN_FRONTEND=noninteractive",
                "apt-get update -qq",
                "apt-get -y -qq upgrade",
                "apt-get install -y -qq unattended-upgrades ca-certificates curl gnupg",
                "dpkg-reconfigure -f noninteractive unattended-upgrades",
            ],
            skipReason: requiresApt
        )
    }

    private static func docker() -> RecipeStep {
        let repository =
            "deb [arch=$(dpkg --print-architecture) "
            + "signed-by=/etc/apt/keyrings/docker.asc] "
            + "https://download.docker.com/linux/ubuntu "
            + "$(. /etc/os-release && echo \"$VERSION_CODENAME\") stable"
        // Логи контейнеров без потолка — самая частая причина внезапно
        // кончившегося диска. Ограничение не стоит ничего.
        let daemon = #"{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}"#
        return RecipeStep(
            id: "docker",
            title: "Docker и Compose с лимитом логов",
            commands: [
                "install -m 0755 -d /etc/apt/keyrings",
                "curl -fsSL https://download.docker.com/linux/ubuntu/gpg"
                    + " -o /etc/apt/keyrings/docker.asc",
                "chmod a+r /etc/apt/keyrings/docker.asc",
                "echo \(Shell.quote(repository)) > /etc/apt/sources.list.d/docker.list",
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
                return profile.dockerPath != nil ? .alreadyDone("docker уже установлен") : nil
            }
        )
    }

    private static func nginx() -> RecipeStep {
        RecipeStep(
            id: "nginx",
            title: "nginx",
            commands: ["apt-get install -y -qq nginx", "systemctl enable --now nginx"],
            skipReason: { profile in
                if let skip = requiresApt(profile) { return skip }
                return profile.hasNginx ? .alreadyDone("nginx уже установлен") : nil
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
            title: "certbot · \(domain)",
            commands: [
                "apt-get install -y -qq certbot python3-certbot-nginx",
                dnsCheck,
                "certbot --nginx --non-interactive --agree-tos"
                    + " -m \(Shell.quote(email)) -d \(Shell.quote(domain))",
            ],
            skipReason: requiresApt
        )
    }

    private static func firewall() -> RecipeStep {
        // Docker пишет правила в iptables мимо UFW, поэтому опубликованный порт
        // открыт наружу, что бы firewall ни думал. Тихо исправить это нельзя —
        // но можно показать.
        let auditPorts =
            "grep -rHnE '^[[:space:]]*-[[:space:]]*\"?[0-9]+:[0-9]+'"
            + " /srv /opt /root --include='*compose*.y*ml' 2>/dev/null"
            + " | grep -v '127\\.0\\.0\\.1'"
            + " | sed 's/^/ВНИМАНИЕ порт наружу мимо UFW: /' || true"
        return RecipeStep(
            id: "ufw",
            title: "UFW: только 22, 80, 443",
            commands: [
                "apt-get install -y -qq ufw",
                "ufw --force reset",
                "ufw default deny incoming",
                "ufw default allow outgoing",
                "ufw allow 22/tcp comment 'ssh'",
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
            title: "закрыть вход по паролю",
            commands: [
                "mkdir -p /etc/ssh/sshd_config.d",
                "printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\n"
                    + "PermitRootLogin prohibit-password\\n'"
                    + " > /etc/ssh/sshd_config.d/10-phosphor.conf",
                "sshd -t",
                "systemctl reload ssh 2>/dev/null || systemctl reload sshd",
            ],
            skipReason: { profile in
                profile.authorizedKeyCount > 0
                    ? nil
                    : .unsupported("нет ни одного ключа — закрывать пароли нельзя")
            }
        )
    }

    /// Steps whose failure must stop the run rather than be reported and passed.
    public static let mustSucceed: Set<String> = ["packages", "docker"]

    /// The step that requires an independent key-based login before it runs.
    public static let needsKeyProof = "passwords"
}
