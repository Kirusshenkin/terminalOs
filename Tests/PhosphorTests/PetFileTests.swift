import Foundation
import Testing

@testable import PetKit

@Suite("Свои питомцы: файл, папка, поведение")
struct PetFileTests {
    /// Пример из docs — он же обязан проходить проверку, иначе документация врёт.
    static let fox: Data = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/pets/fox.json")
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("docs/pets/fox.json must exist for the tests: \(error)")
        }
    }()

    private func json(_ states: String, id: String = "blob", format: Int = 1) -> Data {
        Data(#"{"format":\#(format),"id":"\#(id)","name":"Blob","states":{\#(states)}}"#.utf8)
    }

    private let minimal =
        #""idle":{"frames":[["rb","br"]]},"walk":{"frames":[["rb"]]},"sleep":{"frames":[["r"]]}"#

    @Test("пример из документации читается целиком")
    func exampleDecodes() throws {
        let fox = try PetFile.decode(Self.fox)
        #expect(fox.id == "fox")
        #expect(fox.idle.frames.count == 2)
        #expect(fox.walk.frames.count == 2)
        #expect(fox.blink != nil)
        #expect(fox.walk.frameSeconds == 0.125)
    }

    @Test("минимальный питомец: три состояния, длительности по умолчанию")
    func minimalPet() throws {
        let pet = try PetFile.decode(json(minimal))
        #expect(pet.blink == nil)
        #expect(pet.idle.frameSeconds == 0.5)
        #expect(pet.idle.frames[0].pixels.count == 4)
        #expect(pet.idle.frames[0].id == "pet.blob.idle.0")
    }

    @Test(
        "каждая ошибка называет место",
        arguments: [
            (#""idle":{"frames":[["rb"]]},"walk":{"frames":[["rb"]]}"#, PetFileError.missingState("sleep")),
            (
                #""idle":{"frames":[["rb","b"]]},"walk":{"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#,
                PetFileError.ragged("idle 1")
            ),
            (
                #""idle":{"frames":[["rx"]]},"walk":{"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#,
                PetFileError.unknownInk("idle 1", "x")
            ),
            (
                #""idle":{"frames":[]},"walk":{"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#,
                PetFileError.frameCount("idle")
            ),
            (
                #""idle":{"frames":[["r"]]},"walk":{"frameMs":5,"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#,
                PetFileError.badDuration("walk")
            ),
            (
                #""idle":{"frames":[["r"]]},"run":{"frames":[["r"]]},"walk":{"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#,
                PetFileError.unknownState("run")
            ),
        ])
    func refuses(states: String, expected: PetFileError) {
        #expect(throws: expected) { try PetFile.decode(json(states)) }
    }

    @Test("слишком большой кадр, чужой id и путь из id отклоняются")
    func limits() {
        let wide = String(repeating: "b", count: PetFile.maxSide + 1)
        let big = #""idle":{"frames":[["\#(wide)"]]},"walk":{"frames":[["r"]]},"sleep":{"frames":[["r"]]}"#
        #expect(throws: PetFileError.frameSize("idle 1")) { try PetFile.decode(json(big)) }
        #expect(throws: PetFileError.reservedID("cat")) { try PetFile.decode(json(minimal, id: "cat")) }
        #expect(throws: PetFileError.badID("../x")) { try PetFile.decode(json(minimal, id: "../x")) }
        #expect(throws: PetFileError.unsupportedFormat(2)) { try PetFile.decode(json(minimal, format: 2)) }
        #expect(throws: PetFileError.tooLarge) {
            try PetFile.decode(Data(count: PetFile.maxFileSize + 1))
        }
    }

    @Test("папка: добавить, не задвоить, прочитать, удалить; сломанный файл не прячет остальных")
    func store() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-pets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }  // временная папка теста
        let store = PetStore(directory: directory)
        #expect(await store.load().pets.isEmpty)

        _ = try await store.add(Self.fox)
        await #expect(throws: PetFileError.exists("fox")) { try await store.add(Self.fox) }
        try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = await store.load()
        #expect(loaded.pets.map(\.id) == ["fox"])
        #expect(loaded.problems.keys.sorted() == ["broken.json"])

        await #expect(throws: PetFileError.badID("../fox")) { try await store.delete(id: "../fox") }
        await #expect(throws: PetFileError.notFound("wolf")) { try await store.delete(id: "wolf") }
        try await store.delete(id: "fox")
        #expect(await store.load().pets.isEmpty)
    }

    @Test("свой питомец не выходит из сцены, стоит на полу и спит, пока терминал занят")
    func behaviour() throws {
        let fox = try PetFile.decode(Self.fox)
        var actions: Set<PetAction> = []
        for time in stride(from: 0.0, through: 32.0, by: 0.05) {
            let frame = PetScene.frame(fox, time: time, sinceActivity: nil)
            actions.insert(frame.action)
            let width = Double(frame.sprite.width) * PetScene.pixel
            let height = Double(frame.sprite.height) * PetScene.pixel
            #expect(frame.x >= 0 && frame.x + width <= PetScene.width, "x at \(time)")
            #expect(frame.y + height == PetScene.customFloorY, "feet at \(time)")
        }
        #expect(actions == [.idle, .walk])
        #expect(PetScene.frame(fox, time: 7, sinceActivity: 1).action == .sleep)
        #expect(PetScene.frame(fox, time: 0.05, sinceActivity: nil).sprite == fox.blink?.frames[0])
    }

    @Test("самый большой допустимый питомец тоже помещается")
    func largestFits() throws {
        let row = String(repeating: "b", count: PetFile.maxSide)
        let frame = "[" + Array(repeating: "\"\(row)\"", count: PetFile.maxSide).joined(separator: ",") + "]"
        let states =
            #""idle":{"frames":[\#(frame)]},"walk":{"frames":[\#(frame)]},"sleep":{"frames":[\#(frame)]}"#
        let pet = try PetFile.decode(json(states))
        for time in stride(from: 0.0, through: 16.0, by: 0.1) {
            let placed = PetScene.frame(pet, time: time, sinceActivity: nil)
            #expect(placed.x >= 0 && placed.x + Double(PetFile.maxSide) * PetScene.pixel <= PetScene.width)
            #expect(placed.y >= 0)
        }
    }
}
