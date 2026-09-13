import Foundation
import Testing

@testable import PhosphorUI

@Suite("Раскладка терминала переживает перезапуск")
struct TerminalLayoutTests {
    /// Свой файл на каждый тест: настоящая раскладка пользователя не трогается.
    private func store() -> (TerminalLayoutStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-layout-\(UUID().uuidString)/terminal.json")
        return (TerminalLayoutStore(url: url), url.deletingLastPathComponent())
    }

    @Test("что записали, то и прочитали")
    func roundTrip() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        let layout = TerminalLayout(
            spaces: [host], spaceSessions: [host.uuidString: "build"], focused: host,
            session: "build", secondSession: "side", splitVertical: false)
        store.save(layout)
        #expect(store.load() == layout)
    }

    @Test("файла ещё нет — пустая раскладка, а не падение")
    func missing() {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load() == TerminalLayout())
    }

    @Test("испорченный файл не мешает запуску")
    func broken() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ не json".utf8).write(to: directory.appendingPathComponent("terminal.json"))
        #expect(store.load() == TerminalLayout())
    }

    @Test("раскладка прошлой версии читается: одна вторая панель — это список из неё")
    @MainActor func oldLayoutWithOnePane() throws {
        let (store, directory) = store()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Файл без поля `panes` — именно так писала версия с двумя панелями.
        let json = #"{"spaces":[],"spaceSessions":{},"splitVertical":true,"secondSession":"side"}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("terminal.json"))
        let saved = store.load()
        #expect(saved.panes == nil)
        #expect(saved.secondSession == "side")
        // Так её и разворачивает модель.
        #expect((saved.panes ?? saved.secondSession.map { [$0] } ?? []) == ["side"])
    }

    @Test("имя новой панели — первое свободное")
    @MainActor func paneNames() {
        #expect(AppModel.nextPaneName(taken: ["main"]) == "side")
        #expect(AppModel.nextPaneName(taken: ["main", "side"]) == "side2")
        #expect(AppModel.nextPaneName(taken: ["main", "side", "side2"]) == "side3")
        // Занятое имя не выдаётся повторно: две панели в одной сессии — это
        // одна и та же лента, показанная дважды.
        let taken: Set<String> = ["side", "side2", "side3"]
        #expect(!taken.contains(AppModel.nextPaneName(taken: taken)))
    }

    @Test("удалённый хост уходит из раскладки вместе со своей сессией")
    func forgetsUnknownHosts() {
        let alive = UUID(), gone = UUID()
        let layout = TerminalLayout(
            spaces: [alive, gone],
            spaceSessions: [alive.uuidString: "main", gone.uuidString: "old"],
            focused: gone, session: "main", secondSession: "side", splitVertical: false)
        let kept = layout.keeping(hosts: [alive])
        #expect(kept.spaces == [alive])
        #expect(kept.spaceSessions == [alive.uuidString: "main"])
        // Спейса, в который возвращались, больше нет — значит возвращаться некуда.
        #expect(kept.focused == nil)
        // Сплит и его сессии к хостам не привязаны и остаются как были.
        #expect(kept.session == "main" && kept.secondSession == "side")
        #expect(kept.splitVertical == false)
    }
}
