import Foundation
import Testing

@testable import HostsKit
@testable import PhosphorUI

@Suite("Выбор сервера и журнал ИИ")
@MainActor
struct PickerAndJournalTests {
    @Test("текущий первым, за ним спейсы, потом свежие, остальные по порядку")
    func ordersHosts() {
        let now = Date()
        let old = ServerHost(name: "old", address: "a")
        let seenEarly = ServerHost(name: "early", address: "b", lastSeen: now.addingTimeInterval(-600))
        let seenLate = ServerHost(name: "late", address: "c", lastSeen: now)
        let space = ServerHost(name: "space", address: "d")
        let current = ServerHost(name: "current", address: "e")
        let ordered = HostPicker.ordered(
            [old, seenEarly, seenLate, space, current], current: current.id, spaces: [space.id])
        #expect(ordered.map(\.name) == ["current", "space", "late", "early", "old"])
    }

    @Test("host=<uuid> уходит, когда имя хоста уже есть")
    func dropsHostID() {
        let line = ActivityView.readableArguments("host=8EE590D9 lines=50", hostName: "prod")
        #expect(line == "lines=50")
        #expect(ActivityView.readableArguments("host=8EE590D9", hostName: "") == "host=8EE590D9")
    }

    @Test("причина отказа не повторяется дважды")
    func outcomeOnce() {
        let text = ActivityView.outcome(
            decision: "deny: mcp disabled for this host", summary: "denied: mcp disabled for this host")
        #expect(text == "deny · denied: mcp disabled for this host")
        #expect(ActivityView.outcome(decision: "allow", summary: "a\nb") == "allow · a b")
    }
}
