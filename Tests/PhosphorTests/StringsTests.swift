import Foundation
import Testing

@testable import DockerKit
@testable import HostsKit
@testable import KeysKit
@testable import PhosphorUI
@testable import SessionKit
@testable import AuthKit
@testable import SSHKit
@testable import PhosphorCore
@testable import ProvisionKit

/// Всё, что приходит из пакетов, подписывается по таблице на обоих языках.
///
/// Ошибка здесь тихая: пропущенный ключ показывается на экране самим ключом,
/// а русская строка из пакета — русской строкой в английском интерфейсе.
@Suite("Подписи из пакетов")
struct PackageStringsTests {
    private static let languages = Language.allCases

    @Test("у каждого значения перечислений есть перевод на оба языка", arguments: languages)
    func everyCaseTranslated(language: Language) {
        let strings = Strings(language: language)
        var texts: [String] = []
        texts += [Reach.direct, .socks(host: "127.0.0.1", port: 1080), .jump(hostID: UUID())].map(strings.reach)
        texts += GuardLevel.allCases.map(strings.guardLevel)
        texts += MCPMode.allCases.map(strings.mcpMode)
        texts += [ConnectionEvent.Kind.connected, .disconnected, .failed].map(strings.connectionEvent)
        texts += [Container.State.running, .exited, .paused, .restarting, .created, .dead, .unknown]
            .map(strings.containerState)
        texts += ContainerAction.allCases.map(strings.containerAction)
        let resources: [ResourceAction] = [
            .removeImage(id: "i", name: "n"), .pruneImages, .removeVolume(name: "v"), .pruneVolumes,
            .removeNetwork(id: "i", name: "n"), .pruneNetworks,
        ]
        texts += resources.map(strings.resourceTitle) + resources.map(strings.resourceWarning)
        texts += [.pruneImages, .pruneVolumes, .pruneNetworks].map(strings.resourceSubject)
        texts += [KeyWeakness.dsa, .shortRSA(bits: 2048)].map(strings.keyWeakness)
        texts += [RemoteFile.Kind.symlink, .directory, .file(extension: nil)].map(strings.fileKind)
        texts += PortForward.Direction.allCases.map(strings.forwardDirection)
        // Ненайденный ключ возвращается как есть — `cstate.running`: такого
        // вида у настоящей подписи не бывает.
        for text in texts {
            #expect(text.range(of: #"\b[a-z]+\.[a-zA-Z]+\b"#, options: .regularExpression) == nil, "\(text)")
        }
    }

    @Test("в английском интерфейсе нет кириллицы из пакетов")
    func englishHasNoCyrillic() {
        let strings = Strings(language: .english)
        let samples = [
            strings.reach(.direct), strings.reach(.socks(host: "127.0.0.1", port: 10808)),
            strings.mcpMode(.readOnly), strings.containerState(.exited),
            strings.containerAction(.remove), strings.size(1_073_741_824),
            strings.duration(seconds: 41 * 86_400 + 6 * 3_600),
        ]
        for text in samples {
            #expect(text.range(of: "\\p{Cyrillic}", options: .regularExpression) == nil, "\(text)")
        }
        #expect(strings.duration(seconds: 3_600 * 2 + 840) == "2h 14m")
        #expect(strings.size(1_073_741_824).hasSuffix("GB"))
        #expect(strings.reach(.socks(host: "127.0.0.1", port: 10808)) == "proxy 127.0.0.1:10808")
    }

    @Test("ключи двух таблиц не пересекаются и переведены на оба языка")
    func tablesDisjointAndComplete() {
        #expect(Set(Strings.table.keys).isDisjoint(with: Strings.packageTable.keys))
        for (key, values) in Strings.packageTable {
            #expect(Set(values.keys) == Set(Language.allCases), "\(key)")
        }
    }

    @Test("у каждой причины ошибки есть слова на обоих языках", arguments: languages)
    func everyErrorTranslated(language: Language) {
        let strings = Strings(language: language)
        let errors: [any Error] = [
            ConnectionFailure.proxyDown(host: "127.0.0.1", port: 1080), ConnectionFailure.denied(host: "h"),
            ConnectionFailure.hostKeyChanged(host: "h"), ConnectionFailure.unreachable(address: "h"),
            ConnectionFailure.other(host: "h"),
            TransportError.authenticationFailed, TransportError.hostKeyChanged, TransportError.cancelled,
            TransportError.commandFailed(status: 3, stderr: ""),
            DockerProblem.noSocketAccess, DockerProblem.gone, DockerProblem.notRunning,
            DockerProblem.stopFirst, DockerProblem.inUse,
            ForwardProblem.portTaken(8080), ForwardProblem.noConnection, ForwardProblem.needsPrivilege(80),
            KeyManager.KeyError.wouldLockOut, KeyManager.KeyError.notAKey,
            SecretError.notFound, SecretError.denied, SecretError.enrollmentChanged, SecretError.keychain(-25_300),
            ProfileStoreError.empty, ProfileStoreError.keyLost, ProfileStoreError.enrollmentChanged,
            GateError.unavailable(nil), GateError.lockedOut,
        ]
        for error in errors {
            let text = strings.describe(error)
            #expect(text.range(of: #"\b[a-z]+\.[a-zA-Z]+\b"#, options: .regularExpression) == nil, "\(text)")
            #expect(!text.contains("%@"), "\(text)")
            // Отладочный вид вроде `portTaken(8080)` на экран не попадает.
            #expect(!text.contains("("), "\(text)")
            if language == .english {
                #expect(text.range(of: "\\p{Cyrillic}", options: .regularExpression) == nil, "\(text)")
            }
        }
    }

    @Test("у каждого шага автонастройки есть название и причины на обоих языках", arguments: languages)
    func provisioningTranslated(language: Language) {
        let strings = Strings(language: language)
        let recipe = BuiltInRecipe.base(RecipeInputs(domain: "a.example.com", email: "k@example.com"))
        // Без домена: в нём самом есть точка, и проверка ключей споткнулась бы.
        var texts = recipe.steps.map { strings.stepTitle(id: $0.id, detail: nil) }
        texts += [RecipeStep.Skip.alreadyInstalled("docker"), .needsApt, .noKeys].map(strings.stepSkip)
        texts += [StepFailure.keyNotProven, .stopped, .exitCode(2)].map(strings.stepFailure)
        for text in texts {
            #expect(text.range(of: #"\b[a-z]+\.[a-zA-Z]+\b"#, options: .regularExpression) == nil, "\(text)")
            #expect(!text.contains("%@"), "\(text)")
        }
        let certbot = recipe.steps.first { $0.id == "certbot" }
        #expect(certbot.map { strings.stepTitle(id: $0.id, detail: $0.detail) }?.hasSuffix("· a.example.com") == true)
    }

    @Test("русские подписи остались прежними")
    func russianUnchanged() {
        let strings = Strings(language: .russian)
        #expect(strings.reach(.direct) == "напрямую")
        #expect(strings.reach(.socks(host: "127.0.0.1", port: 10808)) == "прокси 127.0.0.1:10808")
        #expect(strings.duration(seconds: 41 * 86_400 + 6 * 3_600) == "41д 6ч")
        #expect(strings.keyWeakness(.shortRSA(bits: 2048)) == "RSA 2048 бит — короче 3072")
    }
}
