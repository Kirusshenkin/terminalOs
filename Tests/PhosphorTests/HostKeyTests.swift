import Foundation
import Testing

@testable import HostsKit
@testable import SSHKit

@Suite("Ключ хоста")
struct HostKeyTests {
    @Test("названный ключ уходит в ssh вместе с IdentitiesOnly")
    func namedKey() {
        let host = ServerHost(name: "prod", address: "10.0.0.2", identityFile: "~/.ssh/deploy")
        let arguments = SSHInvocation.arguments(host: host, route: .direct, controlPath: "/tmp/x.sock")
        let index = arguments.firstIndex(of: "-i")
        #expect(index.map { arguments[$0 + 1] } == "~/.ssh/deploy")
        #expect(arguments.contains("IdentitiesOnly=yes"))
    }

    @Test("без ключа ssh выбирает сам — ни -i, ни IdentitiesOnly")
    func automatic() {
        let host = ServerHost(name: "prod", address: "10.0.0.2")
        let arguments = SSHInvocation.arguments(host: host, route: .direct, controlPath: "/tmp/x.sock")
        #expect(!arguments.contains("-i"))
        #expect(!arguments.contains("IdentitiesOnly=yes"))
    }

    @Test("профиль, записанный до появления ключа, читается без него")
    func oldProfileDecodes() throws {
        let host = ServerHost(name: "prod", address: "10.0.0.2")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(host)) as? [String: Any] ?? [:]
        json["identityFile"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ServerHost.self, from: data)
        #expect(decoded.identityFile == nil)
        #expect(decoded.address == "10.0.0.2")
    }
}
