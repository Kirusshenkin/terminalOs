public import PhosphorCore
public import SessionKit
public import SwiftUI

/// The terminal pane with the pet corner.
public struct TerminalPane: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if let note = phaseNote {
                    Text(note)
                        .font(style.font(12))
                        .foregroundStyle(isFailure ? style.warning : style.muted)
                        .padding(.bottom, 8)
                }
                TerminalHost(theme: style.theme) { request in
                    Task { @MainActor in model.guardPrompt = GuardPrompt(request: request) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PetCorner(pet: $model.pet) { model.saveAppearance() }
        }
        // Ничего не попадает в буфер обмена и не открывается, пока человек не
        // увидел, что именно. Согласиться вслепую — как раз то, чем пользуется
        // атака через OSC 52.
        .alert(item: $model.guardPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.detail),
                primaryButton: .default(Text("разрешить")) { model.accept(prompt) },
                secondaryButton: .cancel(Text("отклонить"))
            )
        }
    }

    /// Что сейчас с соединением — одной строкой, с причиной.
    private var phaseNote: String? {
        switch model.sessionState.phase {
        case .idle: nil
        case .connecting: "подключаюсь…"
        case .probing: "собираю профиль хоста…"
        case .ready:
            model.sessionState.profile.map {
                "\($0.osName) \($0.osVersion) · аптайм \(ByteFormat.duration(seconds: $0.uptimeSeconds))"
            }
        case .failed(let reason): reason
        }
    }

    private var isFailure: Bool {
        if case .failed = model.sessionState.phase { return true }
        return false
    }

    private func colour(for kind: TerminalLine.Kind) -> Color {
        switch kind {
        case .prompt: style.bright
        case .output: style.text.opacity(0.85)
        case .warning: style.warning
        case .error: style.danger
        }
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
        VStack(alignment: .leading, spacing: 6) {
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
                .frame(width: 240, height: 130)
                .allowsHitTesting(false)
                .opacity(0.62)
        }
        .padding(.leading, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var scene: some View {
        Canvas { context, size in
            let line = Path(CGRect(x: 8, y: size.height - 26, width: size.width - 40, height: 1))
            context.fill(line, with: .color(style.text.opacity(0.16)))

            switch pet {
            case .cat:
                // A box, a ball and a cat on the floor.
                context.stroke(
                    Path(CGRect(x: 22, y: size.height - 74, width: 46, height: 30)),
                    with: .color(style.muted), lineWidth: 1.5)
                context.stroke(
                    Path(ellipseIn: CGRect(x: 168, y: size.height - 46, width: 12, height: 12)),
                    with: .color(style.muted), lineWidth: 1.5)
                context.fill(
                    catBody(at: CGPoint(x: 100, y: size.height - 26)), with: .color(style.text.opacity(0.28)))
            case .glider:
                // A hollow in a trunk, two branches, no floor at all: a sugar
                // glider does not walk, it glides between them.
                context.fill(
                    Path(CGRect(x: 8, y: 4, width: 26, height: size.height - 12)),
                    with: .color(style.text.opacity(0.14)))
                context.stroke(
                    Path(ellipseIn: CGRect(x: 12, y: size.height - 76, width: 18, height: 24)),
                    with: .color(style.muted), lineWidth: 1.4)
                var upper = Path()
                upper.move(to: CGPoint(x: 34, y: 44))
                upper.addCurve(
                    to: CGPoint(x: 160, y: 36),
                    control1: CGPoint(x: 80, y: 40), control2: CGPoint(x: 120, y: 42))
                context.stroke(upper, with: .color(style.muted), lineWidth: 2)
                var lower = Path()
                lower.move(to: CGPoint(x: 36, y: size.height - 30))
                lower.addCurve(
                    to: CGPoint(x: 200, y: size.height - 34),
                    control1: CGPoint(x: 90, y: size.height - 28),
                    control2: CGPoint(x: 150, y: size.height - 26))
                context.stroke(lower, with: .color(style.muted), lineWidth: 2)
                context.fill(gliderBody(at: CGPoint(x: 96, y: 42)), with: .color(style.text.opacity(0.28)))
            }
        }
    }

    private func catBody(at base: CGPoint) -> Path {
        var path = Path()
        let body = CGRect(x: base.x, y: base.y - 38, width: 28, height: 38)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 10, height: 12))
        path.move(to: CGPoint(x: body.minX + 2, y: body.minY + 6))
        path.addLine(to: CGPoint(x: body.minX, y: body.minY - 8))
        path.addLine(to: CGPoint(x: body.minX + 9, y: body.minY + 2))
        path.closeSubpath()
        path.move(to: CGPoint(x: body.maxX - 2, y: body.minY + 6))
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY - 8))
        path.addLine(to: CGPoint(x: body.maxX - 9, y: body.minY + 2))
        path.closeSubpath()
        return path
    }

    private func gliderBody(at base: CGPoint) -> Path {
        var path = Path()
        let body = CGRect(x: base.x, y: base.y - 24, width: 34, height: 26)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 14, height: 12))
        path.move(to: CGPoint(x: body.minX + 3, y: body.minY + 6))
        path.addLine(to: CGPoint(x: body.minX, y: body.minY - 6))
        path.addLine(to: CGPoint(x: body.minX + 9, y: body.minY + 1))
        path.closeSubpath()
        path.move(to: CGPoint(x: body.maxX - 3, y: body.minY + 6))
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY - 6))
        path.addLine(to: CGPoint(x: body.maxX - 9, y: body.minY + 1))
        path.closeSubpath()
        return path
    }
}
