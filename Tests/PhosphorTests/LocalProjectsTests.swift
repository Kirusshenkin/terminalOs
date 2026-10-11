import Foundation
import Testing

@testable import PhosphorUI

@Suite("Проект на этом Маке")
struct LocalProjectsTests {
    @Test("сессия проекта названа по папке")
    func nameFromFolder() {
        let name = LocalProjects.sessionName(
            for: "/Users/me/Documents/project/terminal", directories: [:], live: [])
        #expect(name == "terminal")
    }

    @Test("тот же проект — та же сессия, даже живая")
    func sameProjectSameSession() {
        let path = "/Users/me/work/api"
        let name = LocalProjects.sessionName(for: path, directories: ["api": path], live: ["api"])
        #expect(name == "api")
    }

    @Test("живая сессия с тем же именем из другой папки не перехватывается")
    func clashWithOtherFolder() {
        let name = LocalProjects.sessionName(
            for: "/Users/me/b/api", directories: ["api": "/Users/me/a/api"], live: ["api"])
        #expect(name == "api-2")
    }

    @Test("живая сессия неизвестно откуда тоже не перехватывается")
    func clashWithUnknown() {
        let name = LocalProjects.sessionName(
            for: "/Users/me/api", directories: ["api-2": "/x/api"], live: ["api", "api-2"])
        #expect(name == "api-3")
    }

    @Test("папка снятой сессии имя не держит")
    func staleDirectory() {
        let name = LocalProjects.sessionName(
            for: "/Users/me/b/api", directories: ["api": "/Users/me/a/api"], live: [])
        #expect(name == "api")
    }

    @Test("имя папки чистится до допустимого для tmux; корень — project")
    func sanitized() {
        #expect(LocalProjects.sessionName(for: "/x/my app.v2", directories: [:], live: []) == "my-app-v2")
        #expect(LocalProjects.sessionName(for: "/", directories: [:], live: []) == "project")
    }

    @Test("последние проекты: свежий сверху, без повторов, не больше предела")
    func recent() {
        #expect(LocalProjects.remember("/b", in: ["/a", "/b", "/c"]) == ["/b", "/a", "/c"])
        let many = (1...10).map { "/p\($0)" }
        let kept = LocalProjects.remember("/new", in: many)
        #expect(kept.count == LocalProjects.recentLimit)
        #expect(kept.first == "/new")
    }

    @Test("домашняя папка показывается как ~, соседняя по префиксу — нет")
    func display() {
        #expect(LocalProjects.display("/Users/me", home: "/Users/me") == "~")
        #expect(LocalProjects.display("/Users/me/work/api", home: "/Users/me") == "~/work/api")
        #expect(LocalProjects.display("/Users/meow/api", home: "/Users/me") == "/Users/meow/api")
    }

    @Test("папки проектов переживают перезапуск, старый файл читается без них")
    func layout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-projects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TerminalLayoutStore(url: directory.appendingPathComponent("terminal.json"))
        let layout = TerminalLayout(
            localSession: "api", localDirectories: ["api": "/Users/me/api"],
            plainShellDirectory: "/Users/me", recentProjects: ["/Users/me/api"])
        store.save(layout)
        #expect(store.load() == layout)

        let old = #"{"spaces":[],"spaceSessions":{},"splitVertical":true,"localSession":"main"}"#
        try Data(old.utf8).write(to: directory.appendingPathComponent("terminal.json"))
        let saved = store.load()
        #expect(saved.localSession == "main")
        #expect(saved.localDirectories == nil)
    }
}
