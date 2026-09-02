public import SwiftUI

/// Строка лога контейнера со своим номером.
///
/// Номер — не украшение: `ForEach` по смещению в кольцевом буфере считает
/// новой каждую строку после сдвига, и весь экран мигает вместо одной строки.
public struct LogLine: Identifiable, Sendable, Equatable {
    public let id: UInt64
    public let text: String

    public init(id: UInt64, text: String) {
        self.id = id
        self.text = text
    }
}

/// Сколько движения человек готов терпеть.
///
/// Выключатель обязателен: терминал открыт весь день, и то, что на третьем
/// запуске радует, на трёхсотом раздражает.
public enum MotionAmount: String, CaseIterable, Sendable {
    case full, brief, off

    public var key: String {
        switch self {
        case .full: "motion.full"
        case .brief: "motion.brief"
        case .off: "motion.off"
        }
    }

    /// Множитель длительности. Ноль — движения нет вовсе.
    public var scale: Double {
        switch self {
        case .full: 1
        case .brief: 0.6
        case .off: 0
        }
    }
}

/// Чем показывать подключение к хосту.
public enum ConnectMotion: String, CaseIterable, Sendable {
    case sweep, arc, none

    public var key: String {
        switch self {
        case .sweep: "motion.sweep"
        case .arc: "motion.arc"
        case .none: "motion.none"
        }
    }
}

/// Чем показывать приход новой строки лога.
public enum LogMotion: String, CaseIterable, Sendable {
    case rise, fade, none

    public var key: String {
        switch self {
        case .rise: "motion.rise"
        case .fade: "motion.fade"
        case .none: "motion.none"
        }
    }
}

/// Луч по строке: показывает, что именно этот хост сейчас опрашивают.
///
/// Один проход слева направо, пока идёт соединение; замолчал — значит, ответ
/// получен. Двигается только `transform`, ширина и цвет не пересчитываются.
public struct Sweep: View {
    @Environment(\.style) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let active: Bool
    private let scale: Double
    @State private var shift: CGFloat = -1

    public init(active: Bool, scale: Double = 1) {
        self.active = active
        self.scale = scale
    }

    public var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            style.accent.opacity(0), style.accent.opacity(0.22),
                            style.bright.opacity(0.5), style.accent.opacity(0.22),
                            style.accent.opacity(0),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * 0.55)
                .offset(x: shift * geo.size.width * 1.6)
                .opacity(running ? 1 : 0)
                .onAppear { start() }
                .onChange(of: active) { _, _ in start() }
        }
        .allowsHitTesting(false)
    }

    private var running: Bool { active && !reduceMotion && scale > 0 }

    private func start() {
        guard running else {
            shift = -1
            return
        }
        shift = -1
        withAnimation(.linear(duration: 0.75 * scale).repeatForever(autoreverses: false)) {
            shift = 1
        }
    }
}

/// Дуга проверки: та же, что на входе по отпечатку, только тише и мельче.
public struct ArcTick: View {
    @Environment(\.style) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let active: Bool
    private let scale: Double
    @State private var sweepEnd: CGFloat = 0

    public init(active: Bool, scale: Double = 1) {
        self.active = active
        self.scale = scale
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: sweepEnd)
            .stroke(style.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 12, height: 12)
            .opacity(active ? 1 : 0)
            .onAppear { start() }
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active, !reduceMotion, scale > 0 else {
            sweepEnd = 0
            return
        }
        sweepEnd = 0
        withAnimation(.easeInOut(duration: 1.1 * scale).repeatForever(autoreverses: false)) {
            sweepEnd = 1
        }
    }
}

extension View {
    /// Показывает, что этот хост сейчас опрашивают — тем способом, который
    /// выбран в настройках.
    public func connecting(_ active: Bool, model: AppModel) -> some View {
        modifier(
            ConnectionMotion(active: active, kind: model.connectMotion, scale: model.motion.scale))
    }
}

struct ConnectionMotion: ViewModifier {
    let active: Bool
    let kind: ConnectMotion
    let scale: Double

    func body(content: Content) -> some View {
        content
            .overlay {
                if kind == .sweep { Sweep(active: active, scale: scale) }
            }
            .overlay(alignment: .topTrailing) {
                if kind == .arc { ArcTick(active: active, scale: scale).padding(7) }
            }
            .clipped()
    }
}
