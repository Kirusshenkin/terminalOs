public import DockerKit
public import HostsKit
public import KeysKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit

/// Настройка свежего сервера по рецепту.
@MainActor
extension AppModel {
    /// Готовит рецепт под конкретный сервер и запускает его.
    public func startProvisioning(inputs: RecipeInputs = RecipeInputs()) async {
        guard let session, let profile, !isProvisioning else { return }
        let host = book.hosts.first { $0.id == selectedHost }
        let reach = host.map { book.reach(for: $0) } ?? .direct

        let fresh = ProvisionRunner(
            transport: SystemSSHTransport(host: host ?? ServerHost(name: "", address: ""), reach: reach),
            recipe: BuiltInRecipe.base(inputs),
            profile: profile,
            proveKeyAccess: {
                // Отдельное соединение, а не текущая сессия: смысл проверки в
                // том, что ключ работает сам по себе.
                guard let host else { return false }
                let probe = SystemSSHTransport(host: host, reach: reach)
                defer { Task { await probe.close() } }
                let result = try? await probe.run("true", timeout: .seconds(15))
                return result?.succeeded == true
            }
        )
        runner = fresh
        provisionLog.removeAll()
        isProvisioning = true
        plannedCommands = await fresh.plannedCommands()

        await fresh.observe(
            onLine: { [weak self] line in
                Task { @MainActor in self?.provisionLog.append(line) }
            },
            onProgress: { [weak self] steps in
                Task { @MainActor in self?.provisionSteps = steps }
            }
        )
        await fresh.run()
        isProvisioning = false
        // После настройки профиль устарел: перечитываем, иначе панель будет
        // считать сервер пустым.
        await session.start()
    }

    public func stopProvisioning() {
        Task { await runner?.stop() }
    }

}
