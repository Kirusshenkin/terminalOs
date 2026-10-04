import CryptoKit
import Foundation
import Testing

@testable import PhosphorCore

@Suite("Манифест обновления")
struct UpdateManifestTests {
    private let key = P256.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.derRepresentation.base64EncodedString() }

    private func manifest(url: String = "https://github.com/Kirusshenkin/terminalOs/releases/download/v0.2.1/Phosphor-0.2.1.zip")
        -> Data
    {
        Data(
            """
            {"name":"Phosphor","version":"0.2.1","build":140,"url":"\(url)",
             "size":3,"sha256":"\(SHA256.hash(data: Data("abc".utf8)).map { String(format: "%02x", $0) }.joined())",
             "install":"…"}
            """.utf8)
    }

    @Test("подписанный манифест принимается и читается")
    func acceptsSigned() throws {
        let data = manifest()
        let signature = try key.signature(for: data).derRepresentation
        let parsed = try UpdateManifest.verified(data, signature: signature, publicKey: publicKey)
        #expect(parsed.version == "0.2.1")
        #expect(parsed.isNewer(thanBuild: 137))
        #expect(!parsed.isNewer(thanBuild: 140))
        #expect(parsed.matches(Data("abc".utf8)))
        #expect(!parsed.matches(Data("abd".utf8)))
    }

    @Test("изменённый после подписи манифест отвергается")
    func rejectsTampered() throws {
        let signature = try key.signature(for: manifest()).derRepresentation
        let tampered = manifest(url: "https://github.com/Kirusshenkin/terminalOs/releases/download/v9/evil.zip")
        #expect(throws: UpdateManifest.Problem.badSignature) {
            try UpdateManifest.verified(tampered, signature: signature, publicKey: publicKey)
        }
    }

    @Test("подпись чужим ключом отвергается")
    func rejectsForeignKey() throws {
        let data = manifest()
        let signature = try P256.Signing.PrivateKey().signature(for: data).derRepresentation
        #expect(throws: UpdateManifest.Problem.badSignature) {
            try UpdateManifest.verified(data, signature: signature, publicKey: publicKey)
        }
    }

    @Test("даже подписанная ссылка не из наших релизов — отказ")
    func rejectsForeignURL() throws {
        let data = manifest(url: "https://example.com/Phosphor.zip")
        let signature = try key.signature(for: data).derRepresentation
        #expect(throws: UpdateManifest.Problem.foreignURL) {
            try UpdateManifest.verified(data, signature: signature, publicKey: publicKey)
        }
    }

    @Test("встроенный ключ разбирается")
    func embeddedKeyParses() throws {
        let data = try #require(Data(base64Encoded: UpdateManifest.publicKey))
        _ = try P256.Signing.PublicKey(derRepresentation: data)
    }
}
