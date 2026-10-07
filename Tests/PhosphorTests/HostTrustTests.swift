import Foundation
import Testing

@testable import HostsKit
@testable import SSHKit

@Suite("Первый визит на сервер")
struct HostTrustTests {
    @Test("отпечаток читается из вывода ssh-keygen -l")
    func parsesFingerprints() {
        let listing = """
            256 SHA256:AbCdEf0123456789 10.0.0.2 (ED25519)
            3072 SHA256:ZyXw9876 10.0.0.2 (RSA)

            """
        #expect(ScannedHostKey.fingerprints(listing) == ["ED25519 SHA256:AbCdEf0123456789", "RSA SHA256:ZyXw9876"])
        #expect(ScannedHostKey.fingerprints("garbage").isEmpty)
    }

    @Test("ключ дописывается в known_hosts, не прилипая к последней записи")
    func appendsOnOwnLine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("known_hosts").path
        // Чужой файл без перевода строки в конце — обычное дело после ручной правки.
        try "old.example ssh-ed25519 AAAAold".write(toFile: path, atomically: true, encoding: .utf8)

        let transport = SystemSSHTransport(host: ServerHost(name: "t", address: "10.0.0.2"), route: .direct)
        try await transport.trust(
            ScannedHostKey(lines: "10.0.0.2 ssh-ed25519 AAAAnew\n", fingerprints: []), knownHosts: path)

        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        #expect(lines == ["old.example ssh-ed25519 AAAAold", "10.0.0.2 ssh-ed25519 AAAAnew"])
    }

    @Test("файла known_hosts нет — он появляется только для владельца")
    func createsPrivateFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("known_hosts").path

        let transport = SystemSSHTransport(host: ServerHost(name: "t", address: "10.0.0.2"), route: .direct)
        try await transport.trust(ScannedHostKey(lines: "10.0.0.2 ssh-ed25519 AAAA", fingerprints: []), knownHosts: path)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "10.0.0.2 ssh-ed25519 AAAA\n")
    }
}
