import Testing

@testable import PetKit

@Suite("Pet corner")
struct PetSceneTests {
    /// Every moment of two full cycles, ten times a second.
    private static let moments = stride(from: 0.0, through: 32.0, by: 0.1).map { $0 }

    @Test("every frame is parsed and not empty")
    func framesParse() {
        let ids = PetFrames.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for sprite in PetFrames.all {
            #expect(!sprite.pixels.isEmpty, "\(sprite.id)")
            #expect(sprite.pixels.allSatisfy { $0.x < sprite.width && $0.y < sprite.height })
        }
    }

    @Test("blink closes the eyes and nothing else")
    func blink() {
        #expect(PetFrames.catBlink.pixels.allSatisfy { $0.ink != .eye })
        #expect(PetFrames.catBlink.pixels.count == PetFrames.catSit.pixels.count)
        #expect(PetFrames.gliderBlink.pixels.allSatisfy { $0.ink != .eye })
    }

    @Test("the animal never leaves the scene", arguments: PetKind.allCases)
    func staysInside(kind: PetKind) {
        for time in Self.moments {
            let frame = PetScene.frame(kind, time: time, sinceActivity: nil)
            let width = Double(frame.sprite.width) * PetScene.pixel
            let height = Double(frame.sprite.height) * PetScene.pixel
            #expect(frame.x >= 0 && frame.x + width <= PetScene.width, "x at \(time)")
            #expect(frame.y >= 0 && frame.y + height <= PetScene.height, "y at \(time)")
        }
    }

    @Test("the cat stands on the floor except mid-jump")
    func catOnFloor() {
        for time in Self.moments {
            let frame = PetScene.frame(.cat, time: time, sinceActivity: nil)
            guard frame.action != .jump else { continue }
            let feet = frame.y + Double(frame.sprite.height) * PetScene.pixel
            #expect(feet == PetScene.floorY, "feet at \(time)")
        }
    }

    @Test("the cycle does everything it promises", arguments: PetKind.allCases)
    func cycleActions(kind: PetKind) {
        let actions = Set(Self.moments.map { PetScene.frame(kind, time: $0, sinceActivity: nil).action })
        let expected: Set<PetAction> = kind == .cat ? [.idle, .walk, .jump] : [.idle, .glide, .climb]
        #expect(actions == expected)
    }

    @Test("busy terminal means asleep, quiet means awake", arguments: PetKind.allCases)
    func sleepsWhileYouWork(kind: PetKind) {
        #expect(PetScene.frame(kind, time: 3, sinceActivity: 0).action == .sleep)
        #expect(PetScene.frame(kind, time: 3, sinceActivity: PetScene.wakeAfter - 0.1).snoring)
        #expect(PetScene.frame(kind, time: 3, sinceActivity: PetScene.wakeAfter).action != .sleep)
        #expect(PetScene.frame(kind, time: 3, sinceActivity: nil).action != .sleep)
    }

    @Test("the glider sleeps inside the hollow")
    func gliderInHollow() {
        let frame = PetScene.frame(.glider, time: 0, sinceActivity: 1)
        let hollow = PetScene.hollow
        let centerX = frame.x + Double(frame.sprite.width) * PetScene.pixel / 2
        let centerY = frame.y + Double(frame.sprite.height) * PetScene.pixel / 2
        #expect(abs(centerX - hollow.x) < 1 && abs(centerY - hollow.y) < 1)
        #expect(frame.sprite == PetFrames.gliderSleep)
    }
}

extension PetSceneTests {
    @Test("the walking cat keeps clear of the box and the ball")
    func catAvoidsProps() {
        for time in Self.moments {
            let frame = PetScene.frame(.cat, time: time, sinceActivity: nil)
            guard frame.action == .walk else { continue }
            let right = frame.x + Double(frame.sprite.width) * PetScene.pixel
            #expect(frame.x >= PetScene.box.x + PetScene.box.width && right <= PetScene.ball.x, "at \(time)")
        }
    }

    @Test("the sleeping glider fits inside the hollow")
    func gliderFitsHollow() {
        let sprite = PetFrames.gliderSleep
        #expect(Double(sprite.width) * PetScene.pixel <= PetScene.hollow.radiusX * 2)
        #expect(Double(sprite.height) * PetScene.pixel <= PetScene.hollow.radiusY * 2)
    }
}
