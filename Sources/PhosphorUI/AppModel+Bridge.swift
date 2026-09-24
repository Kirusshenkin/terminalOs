public import Foundation
public import HostsKit
public import MCPBridge

/// Мост для MCP-клиентов.
@MainActor
extension AppModel {
    /// Поднимает локальный сокет и связывает его с исполнителем инструментов.
    ///
    /// Мост живёт, только пока открыто приложение: закрыл окно — доступ пропал.
    /// Это не ограничение, а свойство, на которое можно рассчитывать.
    func startBridge() async {
        guard bridge == nil else { return }
        let runner = ToolRunner(
            policy: policy,
            audit: audit,
            book: { [weak self] in await self?.book ?? HostBook() },
            sessions: { [weak self] id in
                await self?.selectedHost == id ? await self?.session : nil
            },
            edit: { [weak self] change in
                await self?.apply(change)
            },
            confirm: { [weak self] host, what in
                await self?.askConfirmation(host: host, what: what) ?? false
            }
        )
        let server = SocketServer { [weak self] request in
            // Пока человек не разблокировал приложение, мост не отвечает
            // ничем содержательным. Полагаться на то, что профиль ещё не
            // загружен, нельзя: это совпадение, а не защита.
            guard await self?.isUnlocked == true else {
                return BridgeResponse(
                    ok: false, text: await self?.strings("bridge.locked") ?? "locked")
            }
            guard request.method == "call", let tool = request.tool else {
                return BridgeResponse(ok: true, text: "", tools: BridgeLocation.descriptions())
            }
            let result = await runner.call(
                tool,
                arguments: request.arguments ?? [:],
                mode: request.dryRun == true ? .dryRun : .live
            )
            await self?.refreshAudit()
            return BridgeResponse(ok: !result.isError, text: result.text)
        }
        do {
            try await server.start()
            bridge = server
            bridgeError = nil
        } catch {
            bridgeError = "\(strings("bridge.failed")) \(strings.describe(error))"
        }
    }

    func stopBridge() async {
        try? await bridge?.stop()
        bridge = nil
    }

    func refreshAudit() async {
        auditEntries = await audit.entries()
    }

    /// Спрашивает человека и ждёт его ответа.
    ///
    /// Запросы встают в очередь: раньше второй затирал первый, и ответа на
    /// первый не ждал уже никто — вызов у ИИ-клиента висел навсегда.
    /// Ожидание не вечное: висящий вопрос, о котором все забыли, — это молчаливо
    /// открытый доступ. Истёкшее время означает отказ.
    func askConfirmation(host: String, what: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = ConfirmationRequest(host: host, what: what) { answer in
                continuation.resume(returning: answer)
            }
            mcpQueue.append(request)
            Task { [weak self] in
                // Таймер здесь — верхняя граница ожидания, а не способ дождаться.
                try? await Task.sleep(for: Self.confirmationTimeout)
                self?.answer(request.id, allow: false)
            }
        }
    }

    static let confirmationTimeout: Duration = .seconds(60)

    /// Отвечает на запрос из очереди. Второй ответ на тот же запрос ничего не
    /// делает: продолжение возобновляется ровно один раз.
    public func answer(_ id: ConfirmationRequest.ID, allow: Bool) {
        guard let index = mcpQueue.firstIndex(where: { $0.id == id }) else { return }
        let request = mcpQueue.remove(at: index)
        request.answer(allow)
    }

    /// Отказывает всем ждущим разом — когда агент понёсся не туда.
    public func denyAllConfirmations() {
        for request in mcpQueue { answer(request.id, allow: false) }
    }

    /// Первый в очереди — его показывает окно поверх интерфейса.
    public var mcpConfirmation: ConfirmationRequest? {
        get { mcpQueue.first }
        // Окно закрывается само после ответа кнопкой; отдельного «закрыть без
        // ответа» у него нет, поэтому сброс здесь ничего не значит.
        set { _ = newValue }
    }
}

/// Вопрос, который MCP задал человеку.
public struct ConfirmationRequest: Identifiable, Sendable {
    public var id = UUID()
    public var host: String
    public var what: String
    public var asked = Date()
    public var answer: @Sendable (Bool) -> Void
}

@MainActor
extension AppModel {
    /// Применяет правку списка, пришедшую через мост.
    ///
    /// Тем же путём, что и правка руками: та же проверка, та же запись
    /// профиля. Второго способа менять список нет — иначе он однажды
    /// разойдётся с первым.
    func apply(_ change: HostEdit) {
        switch change {
        case .add(let host): addHost(host)
        case .update(let host): update(host)
        case .remove(let id): removeHost(id)
        }
    }
}
