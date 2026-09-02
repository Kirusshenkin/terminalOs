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
            confirm: { [weak self] host, what in
                await self?.askConfirmation(host: host, what: what) ?? false
            }
        )
        let server = SocketServer { [weak self] request in
            // Пока человек не разблокировал приложение, мост не отвечает
            // ничем содержательным. Полагаться на то, что профиль ещё не
            // загружен, нельзя: это совпадение, а не защита.
            guard await self?.isUnlocked == true else {
                return BridgeResponse(ok: false, text: "Phosphor заблокирован — приложи палец")
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
            bridgeError = "мост не поднялся: \(error)"
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
    /// Ожидание не вечное: висящий диалог, о котором все забыли, — это молчаливо
    /// открытый доступ. Истёкшее время означает отказ.
    private func askConfirmation(host: String, what: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = ConfirmationRequest(host: host, what: what) { answer in
                continuation.resume(returning: answer)
            }
            mcpConfirmation = request
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.mcpConfirmation?.id == request.id else { return }
                self.mcpConfirmation = nil
                request.answer(false)
            }
        }
    }
}

/// Вопрос, который MCP задал человеку.
public struct ConfirmationRequest: Identifiable, Sendable {
    public var id = UUID()
    public var host: String
    public var what: String
    public var answer: @Sendable (Bool) -> Void
}
