public import HostsKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// The terminal pane with the pet corner.
public struct TerminalPane: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 0) {
            // Рейл сессий показываем только на живом хосте: у локального шелла
            // сервера нет, а значит и постоянных сессий тоже.
            if model.session != nil, model.persistentSessions {
                SessionRail(model: model)
                Rectangle().fill(style.rule).frame(width: 1)
            }
            terminal
        }
        // Ничего не попадает в буфер обмена и не открывается, пока человек не
        // увидел, что именно. Согласиться вслепую — как раз то, чем пользуется
        // атака через OSC 52.
        .alert(item: $model.guardPrompt) { prompt in
            Alert(
                title: Text(strings(prompt.titleKey)),
                message: Text(prompt.detail),
                primaryButton: .default(Text(strings("common.allow"))) { model.accept(prompt) },
                secondaryButton: .cancel(Text(strings("common.deny")))
            )
        }
    }

    private var terminal: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                if let offer = model.rememberOffer {
                    rememberBanner(offer)
                }
                if let note = phaseNote {
                    Text(note)
                        .font(style.font(12))
                        .foregroundStyle(isFailure ? style.warning : style.muted)
                        .padding(.bottom, 8)
                }
                TerminalHost(theme: style.theme, destination: model.terminalDestination) { request in
                    Task { @MainActor in model.guardPrompt = GuardPrompt(request: request) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PetCorner(pet: $model.pet) { model.saveAppearance() }
        }
    }

    /// Тонкая полоса «запомнить этот сервер?» после подключения на лету.
    /// Данные уже подставлены — человеку остаётся только согласиться.
    private func rememberBanner(_ host: ServerHost) -> some View {
        HStack(spacing: 10) {
            Text("\(strings("term.remember")) \(host.user)@\(host.address)?")
                .font(style.font(12)).foregroundStyle(style.bright)
            Spacer()
            PhButton(strings("term.remember"), kind: .primary) { model.acceptRememberOffer() }
            PhButton(strings("term.nope")) { model.rememberOffer = nil }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(style.surface)
        .padding(.bottom, 8)
    }

    /// Что сейчас с соединением — одной строкой, с причиной.
    private var phaseNote: String? {
        switch model.sessionState.phase {
        case .idle: nil
        case .connecting: strings("term.connecting")
        case .probing: strings("term.probing")
        case .ready:
            model.sessionState.profile.map {
                "\($0.osName) \($0.osVersion) · \(strings("term.uptime")) \(ByteFormat.duration(seconds: $0.uptimeSeconds))"
            }
        case .failed(let reason): reason
        }
    }

    private var isFailure: Bool {
        if case .failed = model.sessionState.phase { return true }
        return false
    }

}

/// The pet's corner: a bounded scene the animals never leave.
///
/// Confining them removes every problem free-roaming would create — text is
/// never covered, the redraw area is small and constant, and clicks outside a
/// sprite pass straight through to text selection.
public struct PetCorner: View {
    @Environment(\.style) private var style
    @Binding var pet: Pet
    private let onChange: () -> Void

    public init(pet: Binding<Pet>, onChange: @escaping () -> Void = {}) {
        self._pet = pet
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Pet.allCases, id: \.self) { option in
                    Button {
                        pet = option
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
                    .buttonStyle(.plain)
                }
            }
            scene
                .frame(width: 260, height: 130)
                .allowsHitTesting(false)
                .opacity(0.4)
        }
        .padding(.trailing, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var scene: some View {
        Canvas { context, size in
            let ink = style.text.opacity(0.34)
            let line = style.muted
            switch pet {
            case .cat: drawCat(&context, size: size, ink: ink, line: line)
            case .glider: drawGlider(&context, size: size, ink: ink, line: line)
            }
        }
    }

    // MARK: - Котёнок

    /// Кот сидит на полу спиной к нам вполоборота: голова, тело, хвост кольцом.
    private func drawCat(
        _ context: inout GraphicsContext, size: CGSize, ink: Color, line: Color
    ) {
        drawCatScenery(&context, size: size, line: line)
        drawCatBody(&context, base: CGPoint(x: 108, y: size.height - 24), ink: ink)
    }

    /// Пол, коробка и мячик — мир кота.
    private func drawCatScenery(
        _ context: inout GraphicsContext, size: CGSize, line: Color
    ) {
        let floor = size.height - 24
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: 6, y: floor))
                $0.addLine(to: CGPoint(x: size.width - 30, y: floor))
            },
            with: .color(style.text.opacity(0.16)), lineWidth: 1)

        // Коробка: без неё это не коты.
        let box = CGRect(x: 18, y: floor - 34, width: 48, height: 34)
        context.stroke(Path(box), with: .color(line), lineWidth: 1.4)
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: box.minX, y: box.minY + 9))
                $0.addLine(to: CGPoint(x: box.maxX, y: box.minY + 9))
            },
            with: .color(line), lineWidth: 1.4)

        // Мячик.
        context.stroke(
            Path(ellipseIn: CGRect(x: size.width - 62, y: floor - 13, width: 13, height: 13)),
            with: .color(line), lineWidth: 1.4)

    }

    /// Сам кот: сидит, хвост кольцом, глаза закрыты.
    private func drawCatBody(_ context: inout GraphicsContext, base: CGPoint, ink: Color) {
        // Хвост: обвивает лапы спереди — так сидят коты.
        var tail = Path()
        tail.move(to: CGPoint(x: base.x + 26, y: base.y - 6))
        tail.addCurve(
            to: CGPoint(x: base.x + 4, y: base.y - 2),
            control1: CGPoint(x: base.x + 46, y: base.y + 4),
            control2: CGPoint(x: base.x + 20, y: base.y + 8))
        context.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))

        // Тело: сидящий силуэт — узкие плечи, широкий низ.
        var body = Path()
        body.move(to: CGPoint(x: base.x + 2, y: base.y))
        body.addCurve(
            to: CGPoint(x: base.x + 5, y: base.y - 30),
            control1: CGPoint(x: base.x - 5, y: base.y - 12),
            control2: CGPoint(x: base.x - 3, y: base.y - 26))
        body.addLine(to: CGPoint(x: base.x + 23, y: base.y - 30))
        body.addCurve(
            to: CGPoint(x: base.x + 28, y: base.y),
            control1: CGPoint(x: base.x + 31, y: base.y - 26),
            control2: CGPoint(x: base.x + 33, y: base.y - 12))
        body.closeSubpath()
        context.fill(body, with: .color(ink))

        // Голова с ушами.
        let head = CGRect(x: base.x + 1, y: base.y - 52, width: 27, height: 24)
        var skull = Path(roundedRect: head, cornerSize: CGSize(width: 11, height: 10))
        skull.move(to: CGPoint(x: head.minX + 3, y: head.minY + 7))
        skull.addLine(to: CGPoint(x: head.minX + 1, y: head.minY - 8))
        skull.addLine(to: CGPoint(x: head.minX + 12, y: head.minY + 1))
        skull.closeSubpath()
        skull.move(to: CGPoint(x: head.maxX - 3, y: head.minY + 7))
        skull.addLine(to: CGPoint(x: head.maxX - 1, y: head.minY - 8))
        skull.addLine(to: CGPoint(x: head.maxX - 12, y: head.minY + 1))
        skull.closeSubpath()
        context.fill(skull, with: .color(ink))

        // Глаза: спит — значит закрыты, две дужки.
        for offset in [CGFloat(8), CGFloat(19)] {
            var eye = Path()
            eye.move(to: CGPoint(x: head.minX + offset - 3, y: head.minY + 12))
            eye.addQuadCurve(
                to: CGPoint(x: head.minX + offset + 3, y: head.minY + 12),
                control: CGPoint(x: head.minX + offset, y: head.minY + 15))
            context.stroke(eye, with: .color(style.accent), lineWidth: 1.4)
        }
    }

    // MARK: - Сахарный поссум

    /// Поссум сидит на ветке: большие глаза, полоса по спине, расправленная
    /// перепонка между запястьем и лодыжкой и длинный пушистый хвост. Пола в
    /// его мире нет — только ветки и дупло.
    private func drawGlider(
        _ context: inout GraphicsContext, size: CGSize, ink: Color, line: Color
    ) {
        drawTree(&context, size: size, line: line)
        drawGliderBody(&context, perch: CGPoint(x: 96, y: 44), ink: ink, line: line)
    }

    /// Ствол с дуплом, ветки и цветок эвкалипта — мир поссума. Пола в нём нет.
    private func drawTree(
        _ context: inout GraphicsContext, size: CGSize, line: Color
    ) {
        // Ствол эвкалипта: слегка сужается кверху, с бороздами коры.
        var trunk = Path()
        trunk.move(to: CGPoint(x: 10, y: size.height))
        trunk.addLine(to: CGPoint(x: 14, y: 2))
        trunk.addLine(to: CGPoint(x: 38, y: 2))
        trunk.addLine(to: CGPoint(x: 42, y: size.height))
        trunk.closeSubpath()
        context.fill(trunk, with: .color(style.text.opacity(0.12)))
        context.stroke(trunk, with: .color(line.opacity(0.7)), lineWidth: 1.2)
        for x in [CGFloat(20), CGFloat(30)] {
            context.stroke(
                Path {
                    $0.move(to: CGPoint(x: x, y: 12))
                    $0.addLine(to: CGPoint(x: x + 2, y: size.height - 6))
                },
                with: .color(line.opacity(0.35)), lineWidth: 1)
        }

        // Дупло, выстланное листьями: дом вместо коробки.
        let hollow = CGRect(x: 16, y: size.height - 62, width: 20, height: 26)
        context.fill(Path(ellipseIn: hollow), with: .color(.black.opacity(0.55)))
        context.stroke(Path(ellipseIn: hollow), with: .color(line), lineWidth: 1.4)
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: hollow.minX + 3, y: hollow.maxY - 5))
                $0.addQuadCurve(
                    to: CGPoint(x: hollow.maxX - 3, y: hollow.maxY - 5),
                    control: CGPoint(x: hollow.midX, y: hollow.maxY - 12))
            },
            with: .color(style.accent.opacity(0.5)), lineWidth: 1.6)

        // Две ветки на разной высоте — по ним он и перелетает.
        var upper = Path()
        upper.move(to: CGPoint(x: 40, y: 46))
        upper.addCurve(
            to: CGPoint(x: size.width - 34, y: 38),
            control1: CGPoint(x: 90, y: 42), control2: CGPoint(x: 140, y: 44))
        context.stroke(upper, with: .color(line), lineWidth: 2.2)

        var lower = Path()
        lower.move(to: CGPoint(x: 42, y: size.height - 26))
        lower.addCurve(
            to: CGPoint(x: size.width - 16, y: size.height - 32),
            control1: CGPoint(x: 100, y: size.height - 24), control2: CGPoint(x: 160, y: size.height - 22))
        context.stroke(lower, with: .color(line), lineWidth: 2.2)

        drawFlower(&context, at: CGPoint(x: size.width - 44, y: size.height - 30))
    }

    /// Цветок эвкалипта: его еда.
    private func drawFlower(_ context: inout GraphicsContext, at flower: CGPoint) {
        for angle in stride(from: -70.0, through: 70.0, by: 35.0) {
            let radians = angle * .pi / 180
            context.stroke(
                Path {
                    $0.move(to: flower)
                    $0.addLine(
                        to: CGPoint(
                            x: flower.x + sin(radians) * 9, y: flower.y - cos(radians) * 9))
                },
                with: .color(style.accent.opacity(0.55)), lineWidth: 1.2)
        }
    }

    /// Сам зверь, сидящий на ветке.
    private func drawGliderBody(
        _ context: inout GraphicsContext, perch: CGPoint, ink: Color, line: Color
    ) {
        // Хвост: длиннее тела и пушистый — у поссума он почти вдвое длиннее.
        var tail = Path()
        tail.move(to: CGPoint(x: perch.x + 30, y: perch.y - 12))
        tail.addCurve(
            to: CGPoint(x: perch.x + 74, y: perch.y - 40),
            control1: CGPoint(x: perch.x + 58, y: perch.y - 6),
            control2: CGPoint(x: perch.x + 74, y: perch.y - 18))
        context.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))

        // Перепонка: от запястья до лодыжки. Ради неё он и планирует.
        var membrane = Path()
        membrane.move(to: CGPoint(x: perch.x + 4, y: perch.y - 16))
        membrane.addQuadCurve(
            to: CGPoint(x: perch.x + 30, y: perch.y - 10),
            control: CGPoint(x: perch.x + 17, y: perch.y + 2))
        membrane.addLine(to: CGPoint(x: perch.x + 26, y: perch.y - 20))
        membrane.closeSubpath()
        context.fill(membrane, with: .color(ink.opacity(0.55)))

        // Тело: вытянутое, а не круглое.
        var body = Path()
        body.move(to: CGPoint(x: perch.x + 6, y: perch.y - 14))
        body.addCurve(
            to: CGPoint(x: perch.x + 30, y: perch.y - 14),
            control1: CGPoint(x: perch.x + 8, y: perch.y - 34),
            control2: CGPoint(x: perch.x + 30, y: perch.y - 32))
        body.addQuadCurve(
            to: CGPoint(x: perch.x + 6, y: perch.y - 14),
            control: CGPoint(x: perch.x + 18, y: perch.y - 6))
        context.fill(body, with: .color(ink))

        // Лапы на ветке.
        for x in [perch.x + 10, perch.x + 24] {
            context.stroke(
                Path {
                    $0.move(to: CGPoint(x: x, y: perch.y - 12))
                    $0.addLine(to: CGPoint(x: x, y: perch.y - 1))
                },
                with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }

        drawGliderHead(&context, perch: perch, ink: ink)
    }

    /// Голова: большие глаза, полоса по лбу, крупные округлые уши.
    private func drawGliderHead(
        _ context: inout GraphicsContext, perch: CGPoint, ink: Color
    ) {
        // Голова: круглая, с чуть вытянутой мордочкой.
        let head = CGRect(x: perch.x - 4, y: perch.y - 42, width: 24, height: 21)
        context.fill(Path(ellipseIn: head), with: .color(ink))
        // Нос.
        context.fill(
            Path(ellipseIn: CGRect(x: head.minX - 4, y: head.midY - 2, width: 8, height: 6)),
            with: .color(ink))

        // Уши: крупные, округлые, посажены высоко.
        for x in [head.minX + 5, head.maxX - 9] {
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: head.minY - 5, width: 8, height: 9)),
                with: .color(ink))
        }

        // Тёмная полоса от носа через лоб — его примета.
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: head.minX - 1, y: head.midY - 1))
                $0.addLine(to: CGPoint(x: head.maxX - 4, y: head.minY + 3))
            },
            with: .color(.black.opacity(0.5)), lineWidth: 2.6)

        // Глаза: непропорционально большие — он ночной.
        for x in [head.minX + 6, head.minX + 15] {
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: head.midY - 4, width: 7, height: 7)),
                with: .color(.black.opacity(0.75)))
            context.fill(
                Path(ellipseIn: CGRect(x: x + 4.4, y: head.midY - 3, width: 2.2, height: 2.2)),
                with: .color(style.accent))
        }
    }
}
