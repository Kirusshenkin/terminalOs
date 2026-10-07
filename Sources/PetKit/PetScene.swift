import Foundation

/// Which animal lives in the corner.
public enum PetKind: String, Sendable, CaseIterable {
    case cat, glider
}

/// What the animal is doing — for the interface and for tests.
public enum PetAction: String, Sendable {
    case idle, walk, jump, glide, climb, sleep
}

/// One frame of the scene: which sprite, where, and which way it faces.
public struct PetFrame: Sendable, Equatable {
    public let sprite: PetSprite
    /// Top-left corner of the sprite in scene points.
    public let x: Double
    public let y: Double
    public let flipped: Bool
    public let action: PetAction
    /// Draw the floating «z»: the animal is asleep.
    public var snoring: Bool { action == .sleep }
}

/// The corner as a pure function of time.
///
/// Nothing here keeps state: given the clock and how long ago the terminal
/// was last busy, the frame is fully determined. That keeps the drawing code
/// trivial and lets tests check every moment of the cycle without a window.
///
/// The one rule the whole feature rests on (plan §14.5): while you work, they
/// sleep. Input or output in the last `wakeAfter` seconds means asleep.
public enum PetScene {
    public static let width = 200.0
    public static let height = 100.0
    /// Scene points per sprite pixel.
    public static let pixel = 2.0
    /// Quiet this long and they wake up.
    public static let wakeAfter = 20.0

    // MARK: Мир котёнка

    public static let floorY = 76.0
    /// Коробка: обязательный предмет, без неё это не коты.
    public static let box = (x: 18.0, y: 42.0, width: 48.0, height: 34.0)
    public static let ball = (x: 150.0, y: 63.0, size: 13.0)

    // MARK: Мир поссума — пола нет вообще

    public static let trunk = (x: 6.0, width: 26.0)
    public static let hollow = (x: 19.0, y: 64.0, radiusX: 12.0, radiusY: 9.0)
    public static let topBranch = (fromX: 32.0, toX: 112.0, y: 36.0)
    public static let lowBranch = (fromX: 32.0, toX: 192.0, y: 84.0)
    public static let flowerX = 176.0

    /// `sinceActivity`: seconds since the terminal last took input or printed
    /// output; nil when it has not done either yet.
    public static func frame(_ kind: PetKind, time: Double, sinceActivity: Double?) -> PetFrame {
        let asleep = sinceActivity.map { $0 < wakeAfter } ?? false
        switch kind {
        case .cat: return asleep ? catSleeping() : cat(at: time)
        case .glider: return asleep ? gliderSleeping() : glider(at: time)
        }
    }

    // MARK: Котёнок

    static let catCycle = 16.0
    static let catHome = 96.0
    static let catWalkRange = (from: 70.0, to: 104.0)

    static func cat(at time: Double) -> PetFrame {
        let t = time.truncatingRemainder(dividingBy: catCycle)
        let sitTop = floorY - Double(PetFrames.catSit.height) * pixel
        switch t {
        case ..<6, 13.6...:
            return PetFrame(sprite: catIdleSprite(t), x: catHome, y: sitTop, flipped: false, action: .idle)
        case ..<12:
            return catWalking(t - 6)
        default:
            return catJumping((t - 12) / 1.6)
        }
    }

    /// Моргает раз в три секунды, хвостом поводит каждые 0,6 секунды.
    static func catIdleSprite(_ t: Double) -> PetSprite {
        if t.truncatingRemainder(dividingBy: 3) < 0.15 { return PetFrames.catBlink }
        return Int(t / 0.6) % 2 == 0 ? PetFrames.catSit : PetFrames.catSitTail
    }

    /// Туда и обратно ровно за шесть секунд — и снова на своём месте.
    static func catWalking(_ elapsed: Double) -> PetFrame {
        let (x, forward) = pingPong(elapsed, home: catHome, from: catWalkRange.from, to: catWalkRange.to)
        let sprite = PetFrames.catWalk[Int(elapsed / 0.125) % 2]
        let y = floorY - Double(sprite.height) * pixel
        return PetFrame(sprite: sprite, x: x, y: y, flipped: forward, action: .walk)
    }

    /// Из дома вправо до края, влево до другого края и обратно домой — ровно
    /// за `seconds`, чтобы прогулка кончалась там же, где началась.
    static func pingPong(
        _ elapsed: Double, home: Double, from: Double, to: Double, seconds: Double = 6
    ) -> (x: Double, forward: Bool) {
        let length = to - from
        guard length > 0 else { return (home, true) }
        let travelled = (home - from + elapsed * 2 * length / seconds)
            .truncatingRemainder(dividingBy: 2 * length)
        let forward = travelled < length
        return (from + (forward ? travelled : 2 * length - travelled), forward)
    }

    /// Дуга на коробку и обратно: `progress` от 0 до 1.
    static func catJumping(_ progress: Double) -> PetFrame {
        let sprite = PetFrames.catWalk[1]
        let height = Double(sprite.height) * pixel
        let target = box.x + 4
        let there = min(1, progress * 2)
        let back = max(0, progress * 2 - 1)
        let x = catHome + (target - catHome) * there - (target - catHome) * back
        // Высота опоры: пол, потом крышка коробки, потом снова пол.
        let support = progress < 0.5 ? floorY - box.height * there : box.y + box.height * back
        let arc = 14 * sin(progress * .pi * 2).magnitude
        return PetFrame(
            sprite: sprite, x: x, y: support - height - arc, flipped: progress >= 0.5, action: .jump)
    }

    static func catSleeping() -> PetFrame {
        let sprite = PetFrames.catSleep
        return PetFrame(
            sprite: sprite, x: 80, y: floorY - Double(sprite.height) * pixel, flipped: false, action: .sleep)
    }

    // MARK: Поссум

    static let gliderCycle = 15.0
    static let gliderPerch = 60.0
    static let gliderLanding = 150.0

    static func glider(at time: Double) -> PetFrame {
        let t = time.truncatingRemainder(dividingBy: gliderCycle)
        let sitHeight = Double(PetFrames.gliderSit.height) * pixel
        let top = topBranch.y - sitHeight
        let low = lowBranch.y - sitHeight
        switch t {
        case ..<6:
            return gliderSitting(at: gliderPerch, y: top, time: t)
        case ..<8.6:
            return gliderGliding((t - 6) / 2.6, from: (gliderPerch, top), to: (gliderLanding, low))
        case ..<12.6:
            return gliderSitting(at: gliderLanding, y: low, time: t)
        default:
            // Обратно наверх — по стволу: вверх поссум не планирует.
            return gliderClimbing((t - 12.6) / 2.4, low: low, top: top)
        }
    }

    static func gliderSitting(at x: Double, y: Double, time: Double) -> PetFrame {
        let blink = time.truncatingRemainder(dividingBy: 3.5) < 0.15
        return PetFrame(
            sprite: blink ? PetFrames.gliderBlink : PetFrames.gliderSit, x: x, y: y, flipped: false,
            action: .idle)
    }

    /// Самый выигрышный кадр из §14.2: прыжок и долгий полёт вниз.
    static func gliderGliding(
        _ progress: Double, from start: (x: Double, y: Double), to end: (x: Double, y: Double)
    ) -> PetFrame {
        let sprite = PetFrames.gliderGlide[Int(progress * 12) % 3 == 0 ? 1 : 0]
        let sitWidth = Double(PetFrames.gliderSit.width) * pixel
        let wide = Double(sprite.width) * pixel
        // Центр зверя идёт по дуге: сначала чуть вверх (прыжок), потом вниз.
        let centerX = start.x + sitWidth / 2 + (end.x - start.x) * progress
        let lift = 10 * sin(progress * .pi)
        let y = start.y + (end.y - start.y) * progress * progress - lift
        return PetFrame(sprite: sprite, x: centerX - wide / 2, y: y, flipped: false, action: .glide)
    }

    static func gliderClimbing(_ progress: Double, low: Double, top: Double) -> PetFrame {
        let trunkX = trunk.x + trunk.width
        let x: Double
        let y: Double
        switch progress {
        case ..<0.45:
            x = gliderLanding + (trunkX - gliderLanding) * (progress / 0.45)
            y = low
        case ..<0.8:
            x = trunkX
            y = low + (top - low) * ((progress - 0.45) / 0.35)
        default:
            x = trunkX + (gliderPerch - trunkX) * ((progress - 0.8) / 0.2)
            y = top
        }
        return PetFrame(sprite: PetFrames.gliderSit, x: x, y: y, flipped: progress < 0.45, action: .climb)
    }

    static func gliderSleeping() -> PetFrame {
        let sprite = PetFrames.gliderSleep
        let width = Double(sprite.width) * pixel
        let height = Double(sprite.height) * pixel
        return PetFrame(
            sprite: sprite, x: hollow.x - width / 2, y: hollow.y - height / 2, flipped: false, action: .sleep)
    }

    // MARK: Свой питомец — пол, и больше ничего

    public static let customFloorY = 92.0
    static let customCycle = 16.0
    static let customMargin = 12.0

    /// The same day as the built-in ones: stand, walk there and back, stand;
    /// asleep while the terminal is busy. Pets are drawn facing right.
    public static func frame(_ pet: PetDefinition, time: Double, sinceActivity: Double?) -> PetFrame {
        if sinceActivity.map({ $0 < wakeAfter }) ?? false {
            return standing(pet.sleep.frame(at: time), action: .sleep)
        }
        let t = time.truncatingRemainder(dividingBy: customCycle)
        if (6..<12).contains(t) { return customWalking(pet, elapsed: t - 6) }
        let sinceBlink = t.truncatingRemainder(dividingBy: 3)
        if let blink = pet.blink, sinceBlink < blink.duration {
            return standing(blink.frame(at: sinceBlink), action: .idle)
        }
        return standing(pet.idle.frame(at: t), action: .idle)
    }

    static func standing(_ sprite: PetSprite, action: PetAction) -> PetFrame {
        let width = Double(sprite.width) * pixel
        return PetFrame(
            sprite: sprite, x: (PetScene.width - width) / 2,
            y: customFloorY - Double(sprite.height) * pixel, flipped: false, action: action)
    }

    /// Гуляет центром: кадры могут быть разной ширины, а шаг — нет.
    static func customWalking(_ pet: PetDefinition, elapsed: Double) -> PetFrame {
        let sprite = pet.walk.frame(at: elapsed)
        let half = Double(pet.walk.maxWidth) * pixel / 2
        let (center, forward) = pingPong(
            elapsed, home: PetScene.width / 2, from: customMargin + half,
            to: PetScene.width - customMargin - half)
        let width = Double(sprite.width) * pixel
        return PetFrame(
            sprite: sprite, x: center - width / 2, y: customFloorY - Double(sprite.height) * pixel,
            flipped: !forward, action: .walk)
    }
}
