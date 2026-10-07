public import AuthKit
public import DockerKit
public import ProvisionKit
public import PhosphorCore
public import SSHKit
public import SessionKit

/// Ошибки пакетов — словами человека: что произошло и что делать.
///
/// Пакеты бросают причины типами; здесь им подбираются слова на языке
/// интерфейса. Отладочный вид ошибки (`commandFailed(status: 1, …)`) на экран
/// не попадает: он ничего не объясняет.
extension Strings {
    /// Любая ошибка, дошедшая до экрана.
    public func describe(_ error: any Error) -> String {
        switch error {
        case let failure as ConnectionFailure: connectionFailure(failure)
        case let failure as TransportError: transport(failure)
        case let problem as DockerProblem: dockerProblem(problem)
        case let problem as ForwardProblem: forwardProblem(problem)
        case let failure as KeyManager.KeyError: keyError(failure)
        case let failure as SecretError: secretError(failure)
        case let failure as ProfileStoreError: profileError(failure)
        case let failure as GateError: gateError(failure)
        case let failure as RecipeFileError: recipeFileError(failure)
        default: error.localizedDescription
        }
    }

    public func connectionFailure(_ failure: ConnectionFailure) -> String {
        switch failure {
        case .proxyDown(let host, let port): format("err.proxyDown", "\(host):\(port)")
        case .denied(let host): format("err.denied", host)
        case .hostKeyChanged(let host): format("err.hostKeyChanged", host)
        case .hostKeyUnknown(let host): format("err.hostKeyUnknown", host)
        case .unreachable(let address): format("err.unreachable", address)
        case .remote(let text): text
        case .other(let host): format("err.connectFailed", host)
        case .route(let problem): routeProblem(problem)
        case .bastion(_, let inner): self("err.viaBastion") + connectionFailure(inner)
        }
    }

    /// То же без имени хоста: транспорт его не знает, а ошибка всплыла
    /// не из подключения, а из действия на уже открытом соединении.
    public func transport(_ failure: TransportError) -> String {
        switch failure {
        case .proxyUnreachable(let host, let port): format("err.proxyDown", "\(host):\(port)")
        case .hostUnreachable(let address): format("err.unreachable", address)
        case .authenticationFailed: self("err.deniedPlain")
        case .hostKeyChanged: self("err.hostKeyChangedPlain")
        case .hostKeyUnknown: self("err.hostKeyUnknownPlain")
        case .commandFailed(let status, let stderr):
            stderr.isEmpty ? format("err.exitCode", "\(status)") : String(stderr.prefix(200))
        case .cancelled: self("err.cancelled")
        case .route(let problem): routeProblem(problem)
        case .bastion(let bastion, let inner):
            self("err.viaBastion") + bastion.name + " — " + transport(inner)
        }
    }

    public func routeProblem(_ problem: RouteProblem) -> String {
        switch problem {
        case .missingBastion(let host): format("err.routeMissing", host)
        case .loop(let host): format("err.routeLoop", host)
        case .tooDeep(let host): format("err.routeDeep", host)
        }
    }
    public func dockerProblem(_ problem: DockerProblem) -> String {
        switch problem {
        case .noSocketAccess: self("err.dockerSocket")
        case .gone: self("err.dockerGone")
        case .notRunning: self("err.dockerNotRunning")
        case .stopFirst: self("err.dockerStopFirst")
        case .inUse: self("err.dockerInUse")
        case .other(let text): text
        }
    }

    /// Итог действия над контейнером — одной строкой.
    public func outcome(_ outcome: ActionOutcome) -> String {
        let title = containerAction(outcome.action)
        switch outcome.failure {
        case nil: return "\(title): \(self("err.done"))"
        case .docker(let problem): return dockerProblem(problem)
        case .connection(let failure): return connectionFailure(failure)
        case .noSession: return self("err.noSession")
        }
    }

    public func forwardProblem(_ problem: ForwardProblem) -> String {
        switch problem {
        case .portTaken(let port): format("err.portTaken", "\(port)")
        case .noConnection: self("err.forwardNoConnection")
        case .needsPrivilege(let port): format("err.portPrivileged", "\(port)")
        case .other(let text): text
        }
    }

    public func keyError(_ failure: KeyManager.KeyError) -> String {
        switch failure {
        case .wouldLockOut: self("err.keyLockOut")
        case .writeFailed(let text): text
        case .notAKey: self("err.notAKey")
        }
    }

    public func secretError(_ failure: SecretError) -> String {
        switch failure {
        case .notFound: self("err.secretMissing")
        case .denied: self("err.secretDenied")
        case .enrollmentChanged: self("vault.enrollmentChanged")
        case .keychain(let status): format("err.keychain", "\(status)")
        }
    }

    public func profileError(_ failure: ProfileStoreError) -> String {
        switch failure {
        case .empty: self("err.profileEmpty")
        case .keyLost: self("vault.keyLost")
        case .enrollmentChanged: self("vault.enrollmentChanged")
        }
    }

    public func gateError(_ failure: GateError) -> String {
        switch failure {
        case .unavailable(let reason): "\(self("auth.unavailable")) \(reason ?? self("auth.noMethod"))"
        case .refused: self("auth.cancelled")
        case .lockedOut: self("auth.lockedOut")
        }
    }

    /// Чем можно войти на этом Маке — строка для экрана входа.
    public func gateCapability(_ capability: GateCapability) -> String {
        var parts: [String] = []
        if capability.hasBiometry { parts.append("Touch ID") }
        if capability.hasWatch { parts.append("Apple Watch") }
        if capability.hasPassword { parts.append(self("auth.password")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Автонастройка

    /// Название шага по его `id`; отличие (домен certbot) — через точку.
    /// У шагов из чужих рецептов название дал автор — оно и показывается.
    public func stepTitle(id: String, title: String? = nil, detail: String?) -> String {
        if let title { return detail.map { "\(title) · \($0)" } ?? title }
        let title = self("recipe.\(id)")
        return detail.map { "\(title) · \($0)" } ?? title
    }

    /// Чего пока нет на этой системе — с её именем, чтобы было ясно, о чём речь.
    public func provisionUnsupported(_ profile: HostProfile) -> String {
        format("prov.unsupportedOS", profile.displayName)
    }

    public func metricsUnsupported(_ profile: HostProfile) -> String {
        format("mon.unsupportedOS", profile.displayName)
    }

    /// Подсказка «нет tmux» с командой под пакетный менеджер сервера, а не
    /// с `apt` для всех: на Маке или Fedora она бы только запутала.
    public func noTmux(_ profile: HostProfile?) -> String {
        guard let command = profile?.installCommand(for: "tmux") else { return self("term.noTmuxNoCommand") }
        return format("term.noTmux", command)
    }

    public func tmuxInstallNote(_ note: TmuxInstall.Note) -> String {
        switch note {
        case .installed: self("tmux.installed")
        case .copied: self("tmux.copied")
        case .failed(let reason): self("tmux.failed") + reason
        case .stillMissing: self("tmux.stillMissing")
        case .noHomebrew: self("tmux.noHomebrew")
        }
    }

    /// Название рецепта: встроенные — на языке интерфейса, чужие — как их
    /// назвал автор.
    public func recipeName(_ recipe: Recipe) -> String {
        recipe.origin == .builtIn ? self("recipe.name.\(recipe.id)") : recipe.name
    }

    public func recipeFileError(_ error: RecipeFileError) -> String {
        switch error {
        case .tooLarge: self("rf.tooLarge")
        case .notJSON(let detail): format("rf.notJSON", detail)
        case .unsupportedFormat(let version): format("rf.format", "\(version)")
        case .badID(let id): format("rf.badID", id)
        case .reservedID(let id): format("rf.reservedID", id)
        case .badName: self("rf.badName")
        case .stepCount(let count): format("rf.stepCount", "\(count)")
        case .unknownOS(let os): format("rf.unknownOS", os)
        case .unknownPackageManager(let manager): format("rf.unknownPM", manager)
        case .badStepTitle(let step): format("rf.badStepTitle", "\(step)")
        case .commandCount(let step): format("rf.commandCount", "\(step)")
        case .badCommand(let step): format("rf.badCommand", "\(step)")
        case .exists(let id): format("rf.exists", id)
        case .cannotRead(let detail): format("rf.cannotRead", detail)
        case .cannotWrite(let detail): format("rf.cannotWrite", detail)
        }
    }

    public func stepSkip(_ skip: RecipeStep.Skip) -> String {
        switch skip {
        case .alreadyInstalled(let tool): format("recipe.installed", tool)
        case .needsApt: self("recipe.needsApt")
        case .needsLinux: self("recipe.needsLinux")
        case .noKeys: self("recipe.noKeys")
        case .alreadyDone: self("recipe.alreadyDone")
        case .noKeysChosen: self("recipe.noKeysChosen")
        case .wouldLockOut: self("recipe.wouldLockOut")
        case .needsRoot: self("recipe.needsRoot")
        }
    }

    public func stepFailure(_ failure: StepFailure) -> String {
        switch failure {
        case .keyNotProven: self("recipe.keyNotProven")
        case .stopped: self("recipe.stopped")
        case .exitCode(let status): format("err.exitCode", "\(status)")
        case .output(let text): text
        case .transport(let error): transport(error)
        }
    }

    /// Строка таблицы с подстановкой на место `%@`.
    func format(_ key: String, _ value: String) -> String {
        self(key).replacingOccurrences(of: "%@", with: value)
    }
}
