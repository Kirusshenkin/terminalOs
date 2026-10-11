import Foundation
import Testing

@testable import PhosphorUI

@Suite("Пульт по всем спейсам")
@MainActor
struct TerminalSpacesTests {
    @Test("превью отрезает пустой низ экрана и держит потолок строк")
    func previewTrimsBottom() {
        let screen = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n\n\n   \n"
        let lines = AppModel.previewLines(screen)
        #expect(lines.count == AppModel.previewLineLimit)
        #expect(lines.last == "line 30")
    }

    @Test("превью выкидывает управляющие символы и хвостовые пробелы")
    func previewStripsControls() {
        let lines = AppModel.previewLines("ok\u{1B}[31m red\u{07}   \n\u{7F}x")
        #expect(lines == ["ok[31m red", "x"])
    }

    @Test("длинная строка обрезается с многоточием")
    func previewCutsWideLines() {
        let lines = AppModel.previewLines(String(repeating: "a", count: 500))
        #expect(lines.first?.count == AppModel.previewLineWidth + 1)
        #expect(lines.first?.hasSuffix("…") == true)
    }

    @Test("пустой экран — пустое превью, а не строки из пробелов")
    func previewEmpty() {
        #expect(AppModel.previewLines("\n\n  \n").isEmpty)
    }

    @Test("адрес сессии переживает путь через уведомление")
    func placeRoundTrip() {
        let host = UUID()
        let places: [AppModel.AgentPlace] = [.local(nil), .local("build"), .remote(host, "main")]
        for place in places {
            #expect(AgentNotifier.decode(AgentNotifier.encode(place)) == place)
        }
    }

    @Test("чужой или битый адрес не превращается в сессию")
    func placeRejectsGarbage() {
        #expect(AgentNotifier.decode("remote:not-a-uuid:main") == nil)
        #expect(AgentNotifier.decode("elsewhere:main") == nil)
        #expect(AgentNotifier.decode("") == nil)
    }

    @Test("снимок экрана берёт сессию целиком, имя в кавычках")
    func captureQuotesName() {
        let command = AppModel.captureCommand(session: "build")
        #expect(command.contains("capture-pane -p -J -t 'build:'"))
    }

    @Test("превью с кириллицей разбирается правильно")
    func previewWithCyrillic() {
        let screen = "привет\nмир\n"
        let lines = AppModel.previewLines(screen)
        #expect(lines.count > 0)
        #expect(lines.first?.contains("привет") == true)
    }

    @Test("превью с эмодзи не ломается")
    func previewWithEmoji() {
        let screen = "test 🔑 key\n🖥️ server\n"
        let lines = AppModel.previewLines(screen)
        #expect(lines.count >= 1)
        #expect(lines.first?.contains("🔑") == true)
    }

    @Test("очень длинная кириллическая строка обрезается с многоточием")
    func previewCutsCyrillicWideLines() {
        let screen = String(repeating: "ё", count: 500)
        let lines = AppModel.previewLines(screen)
        #expect(lines.first?.hasSuffix("…") == true)
    }

    @Test("смешанные окончания строк (CRLF и LF)")
    func previewMixedLineEndings() {
        let screen = "line1\r\nline2\nline3\r\n"
        let lines = AppModel.previewLines(screen)
        #expect(lines.count >= 2)
    }

    @Test("сессия с кириллицей в имени кодируется и декодируется")
    func placeWithCyrillic() {
        let place = AppModel.AgentPlace.local("тест")
        let encoded = AgentNotifier.encode(place)
        let decoded = AgentNotifier.decode(encoded)
        #expect(decoded == place)
    }

    @Test("очень длинное имя сессии выживает round-trip")
    func placeWithLongName() {
        let longName = String(repeating: "a", count: 500)
        let place = AppModel.AgentPlace.local(longName)
        let encoded = AgentNotifier.encode(place)
        let decoded = AgentNotifier.decode(encoded)
        #expect(decoded == place)
    }

    @Test("очень большой экран обрезается по лимиту")
    func previewLimitsSuperLargeScreen() {
        let lines = (1...1000).map { "line \($0)" }.joined(separator: "\n")
        let preview = AppModel.previewLines(lines)
        #expect(preview.count <= AppModel.previewLineLimit)
    }
}
