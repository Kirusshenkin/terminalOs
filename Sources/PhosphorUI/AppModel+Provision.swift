public import DockerKit
public import Foundation
public import HostsKit
public import KeysKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit

/// Настройка сервера по рецепту: выбор, план до запуска, сам прогон.
@MainActor
extension AppModel {
    /// Сколько событий настройки может ждать главного потока: как и сам лог,
    /// очередь ограничена — при переполнении теряются самые старые строки.
    static let provisionEventBuffer = 4_000

    private var provisionHost: ServerHost? { book.hosts.first { $0.id == selectedHost } }

    /// Встроенные рецепты и свои — в порядке, в котором их предлагает экран.
    public var availableRecipes: [Recipe] {
        BuiltInRecipe.all(recipeInputs()) + userRecipes
    }

    public var selectedRecipe: Recipe? {
        availableRecipes.first { $0.id == selectedRecipeID }
    }

    /// Группа хоста, если у неё может быть свой рецепт.
    public var provisionGroup: HostGroup? { provisionHost.flatMap { book.group(for: $0) } }

    /// Параметры встроенных рецептов для этого хоста.
    func recipeInputs() -> RecipeInputs {
        let chosen = localKeys.filter { provisionKeyIDs.contains($0.id) }
        // Ключ подключения остаётся, если он среди выбранных: либо названный в
        // карточке хоста, либо тот, что сервер принял в этой сессии.
        let identity = provisionHost?.identityFile.map { ($0 as NSString).expandingTildeInPath }
        let kept =
            chosen.contains { $0.id == identity }
            || (myFingerprint.map { current in chosen.contains { $0.fingerprint == current } } ?? false)
        return RecipeInputs(
            sshPort: provisionHost?.port ?? 22,
            keys: chosen.map(\.publicLine),
            removeOtherKeys: removeOtherKeys,
            connectionKeyKept: kept)
    }

    /// План до запуска: какие шаги пойдут, какие пропустятся и почему, и
    /// точный список команд. Согласиться вслепую нельзя — поэтому он есть
    /// раньше кнопки, а не после неё.
    public func refreshProvisionPlan() {
        guard !isProvisioning else { return }
        guard let profile, let recipe = selectedRecipe else {
            provisionSteps = []
            plannedCommands = []
            return
        }
        let plan = recipe.plan(for: profile)
        provisionSteps = plan.map { step, skip in
            StepProgress(
                id: step.id, title: step.title, detail: step.detail,
                status: skip.map { .skipped($0) } ?? .waiting)
        }
        plannedCommands = plan.compactMap { step, skip in skip == nil ? step : nil }
    }

    /// Выбор по умолчанию: рецепт группы, если он есть и подходит, иначе базовый.
    public func chooseDefaultRecipe() {
        let groupRecipe = provisionGroup?.recipeID
        if let groupRecipe, availableRecipes.contains(where: { $0.id == groupRecipe }) {
            selectedRecipeID = groupRecipe
        } else if !availableRecipes.contains(where: { $0.id == selectedRecipeID }) {
            selectedRecipeID = "base"
        } else {
            refreshProvisionPlan()
        }
    }

    /// Делает выбранный рецепт рецептом группы хоста.
    public func makeSelectedRecipeGroupDefault() {
        guard let group = provisionGroup, let index = book.groups.firstIndex(where: { $0.id == group.id })
        else { return }
        book.groups[index].recipeID = selectedRecipeID == "base" ? nil : selectedRecipeID
        scheduleSave()
    }

    public func loadRecipes() async {
        let loaded = await recipeStore.load()
        userRecipes = loaded.recipes
        recipeProblems = loaded.problems
        chooseDefaultRecipe()
    }

    public func importRecipe(from url: URL) async {
        do {
            let recipe = try await recipeStore.importFile(at: url)
            recipeMessage = strings("prov.imported") + recipe.name
            await loadRecipes()
            selectedRecipeID = recipe.id
        } catch {
            recipeMessage = strings.recipeFileError(error)
        }
    }

    public func deleteRecipe(_ recipe: Recipe) async {
        guard recipe.origin == .file else { return }
        do {
            try await recipeStore.delete(id: recipe.id)
            recipeMessage = nil
        } catch {
            recipeMessage = strings.recipeFileError(error)
        }
        // Рецепт группы, которого больше нет, — молчаливая ловушка: забываем его.
        for index in book.groups.indices where book.groups[index].recipeID == recipe.id {
            book.groups[index].recipeID = nil
            scheduleSave()
        }
        await loadRecipes()
    }

    /// Чужой рецепт запускается только из экрана со всеми его командами.
    public func requestProvisioning() async {
        guard let recipe = selectedRecipe else { return }
        if recipe.origin == .file {
            showsPlannedCommands = true
        } else {
            await startProvisioning()
        }
    }

    /// Готовит рецепт под конкретный сервер и запускает его.
    public func startProvisioning() async {
        guard let session, let profile, let recipe = selectedRecipe, !isProvisioning else { return }
        showsPlannedCommands = false
        let host = provisionHost
        let route = host.map { book.route(for: $0) } ?? .direct

        let fresh = ProvisionRunner(
            transport: SystemSSHTransport(host: host ?? ServerHost(name: "", address: ""), route: route),
            recipe: recipe,
            profile: profile,
            proveKeyAccess: {
                // Отдельное соединение, а не текущая сессия: смысл проверки в
                // том, что ключ работает сам по себе.
                guard let host else { return false }
                let probe = SystemSSHTransport(host: host, route: route)
                defer { Task { await probe.close() } }
                let result = try? await probe.run("true", timeout: .seconds(15))
                return result?.succeeded == true
            }
        )
        runner = fresh
        provisionLog.removeAll()
        isProvisioning = true
        plannedCommands = await fresh.plannedCommands()

        // Строки и шаги идут одной очередью к одному читателю: отдельный Task
        // на каждую строку не гарантирует порядка, и лог мог перемешаться,
        // а старое состояние шагов — перетереть новое (#29).
        let (events, sink) = AsyncStream<ProvisionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.provisionEventBuffer))
        let reader = Task { @MainActor [weak self] in
            for await event in events {
                switch event {
                case .line(let line): self?.provisionLog.append(line)
                case .steps(let steps): self?.provisionSteps = steps
                }
            }
        }
        await fresh.observe(
            onLine: { sink.yield(.line($0)) },
            onProgress: { sink.yield(.steps($0)) }
        )
        await fresh.run()
        sink.finish()
        await reader.value
        isProvisioning = false
        // После настройки профиль устарел: перечитываем, иначе панель будет
        // считать сервер пустым.
        await session.start()
    }

    public func stopProvisioning() {
        Task { await runner?.stop() }
    }
}

/// Что сообщает настройка сервера по ходу дела, в порядке, в котором случилось.
enum ProvisionEvent: Sendable {
    case line(String)
    case steps([StepProgress])
}
