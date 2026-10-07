import PetKit
public import SwiftUI

/// The pet's corner: a bounded scene the animals never leave.
///
/// Confining them removes every problem free-roaming would create — text is
/// never covered, the redraw area is small and constant, and clicks outside a
/// sprite pass straight through to text selection.
///
/// What the animal does is decided by `PetScene`; this view only paints the
/// frame it is given. While the terminal is busy the animal sleeps.
public struct PetCorner: View {
    @Environment(\.style) private var style
    @Environment(\.controlActiveState) private var activeState
    @Binding var pet: Pet
    private let onChange: () -> Void
    private let showsPicker: Bool
    /// When the terminal on screen last took input or printed output.
    private let lastActivity: () -> ContinuousClock.Instant?

    public init(
        pet: Binding<Pet>, showsPicker: Bool = true,
        lastActivity: @escaping () -> ContinuousClock.Instant? = { nil },
        onChange: @escaping () -> Void = {}
    ) {
        self._pet = pet
        self.showsPicker = showsPicker
        self.lastActivity = lastActivity
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if showsPicker { picker }
            // Восемь кадров в секунду хватает пиксельному зверю; в фоне — ни одного.
            TimelineView(.animation(minimumInterval: 1.0 / 8, paused: activeState == .inactive)) { timeline in
                scene(at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: PetScene.width, height: PetScene.height)
            .allowsHitTesting(false)
            .opacity(0.55)
        }
        .padding(.trailing, 4)
        .padding(.bottom, 8)
    }

    private var picker: some View {
        HStack(spacing: 6) {
            ForEach(Pet.allCases, id: \.self) { option in
                Button {
                    pet = option
                    onChange()
                } label: {
                    Text(option.title)
                        .font(style.font(10))
                        .tracking(1.6)
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .foregroundStyle(pet == option ? style.background : style.muted)
                        .background(pet == option ? style.accent : .clear)
                        .overlay(
                            Rectangle().stroke(
                                pet == option ? style.accent : style.text.opacity(0.3), lineWidth: 1
                            ))
                }
                .buttonStyle(PressFeedback())
            }
        }
    }

    private func scene(at time: Double) -> some View {
        let kind: PetKind = pet == .cat ? .cat : .glider
        let quiet = lastActivity().map { (ContinuousClock.now - $0).seconds }
        let frame = PetScene.frame(kind, time: time, sinceActivity: quiet)
        let inks = PetInks(style: style)
        return Canvas { context, _ in
            switch kind {
            case .cat: drawRoom(&context)
            case .glider: drawTree(&context)
            }
            draw(frame, inks: inks, into: &context)
            if frame.snoring { drawSnore(&context, above: frame, time: time) }
        }
    }

    // MARK: - Зверь

    private func draw(_ frame: PetFrame, inks: PetInks, into context: inout GraphicsContext) {
        guard let paths = PetPaths.byID[frame.sprite.id] else { return }
        var local = context
        local.translateBy(x: frame.x, y: frame.y)
        if frame.flipped {
            local.translateBy(x: Double(frame.sprite.width) * PetScene.pixel, y: 0)
            local.scaleBy(x: -1, y: 1)
        }
        for (ink, path) in paths {
            local.fill(path, with: .color(inks[ink]))
        }
    }

    /// «z» поднимается и тает над спящим — три буквы со сдвигом по фазе.
    private func drawSnore(_ context: inout GraphicsContext, above frame: PetFrame, time: Double) {
        let origin = CGPoint(
            x: frame.x + Double(frame.sprite.width) * PetScene.pixel - 4, y: frame.y - 2)
        for index in 0..<3 {
            let phase = (time / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let text = Text(verbatim: "z")
                .font(style.font(8 + Double(index) * 2))
                .foregroundStyle(style.accent.opacity(1 - phase))
            context.draw(
                text, at: CGPoint(x: origin.x + phase * 14 + Double(index) * 3, y: origin.y - phase * 22))
        }
    }

    // MARK: - Мир котёнка

    private func drawRoom(_ context: inout GraphicsContext) {
        let line = style.muted
        let floor = PetScene.floorY
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: 6, y: floor))
                $0.addLine(to: CGPoint(x: PetScene.width - 6, y: floor))
            },
            with: .color(style.text.opacity(0.2)), lineWidth: 1)

        let box = PetScene.box
        let rect = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        context.fill(Path(rect), with: .color(style.text.opacity(0.06)))
        context.stroke(Path(rect), with: .color(line), lineWidth: 1.4)
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: rect.minX, y: rect.minY + 9))
                $0.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 9))
            },
            with: .color(line), lineWidth: 1.4)

        let ball = PetScene.ball
        context.stroke(
            Path(ellipseIn: CGRect(x: ball.x, y: ball.y, width: ball.size, height: ball.size)),
            with: .color(line), lineWidth: 1.4)
    }

    // MARK: - Мир поссума

    private func drawTree(_ context: inout GraphicsContext) {
        let line = style.muted
        let trunk = PetScene.trunk
        let rect = CGRect(x: trunk.x, y: 0, width: trunk.width, height: PetScene.height)
        context.fill(Path(rect), with: .color(style.text.opacity(0.1)))
        context.stroke(Path(rect), with: .color(line.opacity(0.7)), lineWidth: 1.2)

        let hollow = PetScene.hollow
        let hole = CGRect(
            x: hollow.x - hollow.radiusX, y: hollow.y - hollow.radiusY,
            width: hollow.radiusX * 2, height: hollow.radiusY * 2)
        context.fill(Path(ellipseIn: hole), with: .color(.black.opacity(0.55)))
        context.stroke(Path(ellipseIn: hole), with: .color(line), lineWidth: 1.2)

        for branch in [PetScene.topBranch, PetScene.lowBranch] {
            context.stroke(
                Path {
                    $0.move(to: CGPoint(x: branch.fromX, y: branch.y))
                    $0.addLine(to: CGPoint(x: branch.toX, y: branch.y))
                },
                with: .color(line), lineWidth: 2)
        }

        // Цветок эвкалипта на нижней ветке: его еда.
        let flower = CGPoint(x: PetScene.flowerX, y: PetScene.lowBranch.y - 2)
        for step in -2...2 {
            let angle = Double(step) * 0.6 - .pi / 2
            context.stroke(
                Path {
                    $0.move(to: flower)
                    $0.addLine(to: CGPoint(x: flower.x + cos(angle) * 7, y: flower.y + sin(angle) * 7))
                },
                with: .color(style.accent.opacity(0.7)), lineWidth: 1)
        }
    }
}

/// Цвета ролей из темы. Считаются раз на кадр, а не на каждый пиксель.
private struct PetInks {
    let body: Color
    let rim: Color
    let eye: Color
    let stripe: Color
    let nose: Color

    init(style: Style) {
        body = style.text.opacity(0.22)
        rim = style.accent
        eye = style.bright
        stripe = style.muted
        nose = style.accent
    }

    subscript(ink: PetSprite.Ink) -> Color {
        switch ink {
        case .body: body
        case .rim: rim
        case .eye: eye
        case .stripe: stripe
        case .nose: nose
        }
    }
}

/// Пиксели каждого кадра, собранные в один `Path` на чернило. Строятся один
/// раз при первом обращении: в отрисовке кадра нет ни одной аллокации пути.
private enum PetPaths {
    static let byID: [String: [(PetSprite.Ink, Path)]] = Dictionary(
        uniqueKeysWithValues: PetFrames.all.map { sprite in
            let grouped = Dictionary(grouping: sprite.pixels, by: \.ink)
            let paths = PetSprite.Ink.allCases.compactMap { ink -> (PetSprite.Ink, Path)? in
                guard let pixels = grouped[ink] else { return nil }
                var path = Path()
                for pixel in pixels {
                    path.addRect(
                        CGRect(
                            x: Double(pixel.x) * PetScene.pixel, y: Double(pixel.y) * PetScene.pixel,
                            width: PetScene.pixel, height: PetScene.pixel))
                }
                return (ink, path)
            }
            return (sprite.id, paths)
        })
}

extension Duration {
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
