import Foundation
import Testing

@testable import AuthKit
@testable import PhosphorUI

/// Очередь пишущих действий ИИ.
///
/// Раньше второй запрос затирал первый, и первый не получал ответа никогда:
/// вызов у ИИ-клиента висел до перезапуска. Здесь каждый запрос должен
/// дождаться ровно своего ответа.
@Suite("Очередь одобрений ИИ")
@MainActor
struct ConfirmationQueueTests {
    private func model() -> AppModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID().uuidString).phosphor")
        return AppModel(profiles: ProfileStore(store: MemorySecretStore(), url: url))
    }

    /// Ждёт, пока в очереди окажется нужное число запросов: готовность —
    /// по факту, без сна наугад.
    private func waitForQueue(_ model: AppModel, count: Int) async {
        while model.mcpQueue.count < count { await Task.yield() }
    }

    @Test("два запроса подряд: каждый получает свой ответ, в любом порядке")
    func eachGetsItsOwnAnswer() async {
        let model = model()
        async let first = model.askConfirmation(host: "a", what: "rm one")
        async let second = model.askConfirmation(host: "b", what: "rm two")
        await waitForQueue(model, count: 2)
        let ids = model.mcpQueue.map(\.id)
        #expect(model.mcpConfirmation?.id == ids[0])

        model.answer(ids[1], allow: true)
        model.answer(ids[0], allow: false)
        let answers = await (first, second)
        // Порядок постановки в очередь у async let не гарантирован — сверяем набор.
        #expect(Set([answers.0, answers.1]) == [true, false])
        #expect(model.mcpQueue.isEmpty)
    }

    @Test("повторный ответ на тот же запрос ничего не ломает")
    func secondAnswerIsIgnored() async {
        let model = model()
        async let result = model.askConfirmation(host: "a", what: "restart")
        await waitForQueue(model, count: 1)
        let id = model.mcpQueue[0].id
        model.answer(id, allow: true)
        model.answer(id, allow: false)
        #expect(await result == true)
    }

    @Test("«отказать всем» закрывает всю очередь отказом")
    func denyAll() async {
        let model = model()
        async let one = model.askConfirmation(host: "a", what: "1")
        async let two = model.askConfirmation(host: "a", what: "2")
        async let three = model.askConfirmation(host: "a", what: "3")
        await waitForQueue(model, count: 3)
        model.denyAllConfirmations()
        let answers = await [one, two, three]
        #expect(answers == [false, false, false])
        #expect(model.mcpQueue.isEmpty)
    }
}
