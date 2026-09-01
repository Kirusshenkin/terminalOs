public import Foundation
public import HostsKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit

/// Ход выполнения одного шага.
public struct StepProgress: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case waiting
        case running
        case done
        case skipped(String)
        case failed(String)
    }

    public var id: String
    public var title: String
    public var status: Status = .waiting

    public var isFinished: Bool {
        switch status {
        case .waiting, .running: false
        case .done, .skipped, .failed: true
        }
    }
}

/// Выполняет рецепт на сервере, шаг за шагом, с живым выводом.
///
/// Три правила, из которых состоит вся осторожность этой штуки:
/// команды показываются целиком **до** запуска; шаг, который уже сделан,
/// пропускается, а не повторяется; закрытие входа по паролю выполняется
/// последним и только после того, как отдельное соединение по ключу реально
/// открылось. Обычные скрипты ломаются именно на третьем.
public actor ProvisionRunner {
    public enum RunError: Error, Equatable {
        /// Ключ не проверен, а шаг закрывает пароли — это прямой путь к тому,
        /// чтобы запереть себя снаружи.
        case keyNotProven
        case stopped
    }

    private let transport: any SSHTransport
    private let recipe: Recipe
    private let profile: HostProfile
    /// Проверка, что вход по ключу работает независимо от текущей сессии.
    private let proveKeyAccess: @Sendable () async -> Bool

    private var progress: [StepProgress]
    private var stopRequested = false
    private var onLine: (@Sendable (String) -> Void)?
    private var onProgress: (@Sendable ([StepProgress]) -> Void)?

    public init(
        transport: any SSHTransport,
        recipe: Recipe,
        profile: HostProfile,
        proveKeyAccess: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.transport = transport
        self.recipe = recipe
        self.profile = profile
        self.proveKeyAccess = proveKeyAccess
        self.progress = recipe.steps.map { StepProgress(id: $0.id, title: $0.title) }
    }

    public var steps: [StepProgress] { progress }

    /// Все команды, которые могут уйти на сервер, в порядке выполнения.
    ///
    /// Показывается до запуска целиком: скрытых действий здесь нет.
    public func plannedCommands() -> [(step: String, commands: [String])] {
        recipe.plan(for: profile).compactMap { step, skip in
            skip == nil ? (step.title, step.commands) : nil
        }
    }

    public func observe(
        onLine: @escaping @Sendable (String) -> Void,
        onProgress: @escaping @Sendable ([StepProgress]) -> Void
    ) {
        self.onLine = onLine
        self.onProgress = onProgress
        onProgress(progress)
    }

    /// Просит остановиться. Текущий шаг доигрывается до конца: обрывать
    /// установку пакетов на середине хуже, чем дать ей закончиться.
    public func stop() {
        stopRequested = true
    }

    public func run() async {
        let plan = recipe.plan(for: profile)
        for (index, entry) in plan.enumerated() {
            if stopRequested {
                mark(index, .failed("остановлено"))
                break
            }
            if let skip = entry.skip {
                mark(index, .skipped(Self.describe(skip)))
                continue
            }
            if entry.step.id == BuiltInRecipe.needsKeyProof, await !proveKeyAccess() {
                mark(index, .failed("вход по ключу не подтверждён — пароли не закрываю"))
                continue
            }
            mark(index, .running)
            let failure = await execute(entry.step)
            mark(index, failure.map { .failed($0) } ?? .done)
            // Шаги из обязательных валят весь прогон: ставить nginx поверх
            // неустановленных пакетов бессмысленно.
            if failure != nil, BuiltInRecipe.mustSucceed.contains(entry.step.id) { break }
        }
    }

    /// Выполняет команды шага, возвращая описание ошибки или nil.
    private func execute(_ step: RecipeStep) async -> String? {
        for command in step.commands {
            onLine?("$ \(command)")
            do {
                let result = try await transport.run(command, timeout: .seconds(600))
                for line in result.stdout.split(separator: "\n") { onLine?(String(line)) }
                for line in result.stderr.split(separator: "\n") { onLine?(String(line)) }
                if !result.succeeded {
                    return String(result.stderr.prefix(160))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .ifEmpty("код возврата \(result.status)")
                }
            } catch {
                return "\(error)"
            }
        }
        return nil
    }

    private func mark(_ index: Int, _ status: StepProgress.Status) {
        guard progress.indices.contains(index) else { return }
        progress[index].status = status
        onProgress?(progress)
    }

    private static func describe(_ skip: RecipeStep.Skip) -> String {
        switch skip {
        case .alreadyDone(let reason): reason
        case .unsupported(let reason): reason
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
