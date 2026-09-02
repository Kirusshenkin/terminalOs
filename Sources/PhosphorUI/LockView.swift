public import SwiftUI

/// The unlock moment.
///
/// Three beats: the arc reads the finger, a flash confirms it, then the glyph
/// collapses into a bright line that sweeps the screen open — the way a CRT
/// switched on. It runs once per session, which is exactly why it is allowed to
/// be the loudest thing in the app.
///
/// Everything animates `transform` and `opacity` equivalents only: scale,
/// offset, opacity and one stroke trim. No blur, no shadow animation, nothing
/// the GPU cannot composite.
public struct LockView: View {
    @Environment(\.style) private var style
    private let strings: Strings
    private let welcome: Welcome
    /// Что доступно на этом Маке — показываем только это.
    private let capability: String
    private let error: String?
    private let onUnlock: () async -> Void

    @State private var phase: Phase = .waiting
    @State private var arc: CGFloat = 0
    @State private var flash: Double = 0
    @State private var glyphScale: CGSize = CGSize(width: 1, height: 1)
    @State private var glyphOpacity: Double = 1
    @State private var lineOpacity: Double = 0
    @State private var sweep: CGFloat = 0.004
    @State private var konami = KonamiWatcher()
    @State private var somersault = false

    private enum Phase { case waiting, reading, opening, open }

    public init(
        strings: Strings,
        welcome: Welcome,
        capability: String,
        error: String? = nil,
        onUnlock: @escaping () async -> Void
    ) {
        self.strings = strings
        self.welcome = welcome
        self.capability = capability
        self.error = error
        self.onUnlock = onUnlock
    }

    public var body: some View {
        CRTFrame {
            ZStack {
                revealed
                    .scaleEffect(x: 1, y: sweep, anchor: .center)
                    .opacity(sweep > 0.01 ? 1 : 0)

                Rectangle()
                    .fill(style.bright)
                    .frame(height: 2)
                    .opacity(lineOpacity)

                if phase != .open {
                    glyph
                        .scaleEffect(x: glyphScale.width, y: glyphScale.height)
                        .opacity(glyphOpacity)
                }

                Rectangle().fill(style.accent).opacity(flash).allowsHitTesting(false)
            }
        }
        .onAppear { boot() }
    }

    // MARK: - Pieces

    private var glyph: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .stroke(style.muted.opacity(0.4), lineWidth: 2)
                    .frame(width: 124, height: 124)
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(style.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: 124, height: 124)
                    .rotationEffect(.degrees(-90))
                Fingerprint()
                    .stroke(style.accent, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                    .frame(width: 84, height: 84)
                    .opacity(phase == .waiting ? 0.55 : 1)
                    .rotationEffect(.degrees(somersault ? 360 : 0))
            }
            .contentShape(Circle())
            .onTapGesture { begin() }

            VStack(spacing: 9) {
                Text(strings(phase == .waiting ? "lock.touch" : "lock.reading"))
                    .font(style.font(15))
                    .foregroundStyle(style.text)
                Text(strings("lock.noAccount"))
                    .font(style.font(12))
                    .foregroundStyle(style.muted)
                    .multilineTextAlignment(.center)
                Text(capability)
                    .font(style.font(11))
                    .foregroundStyle(style.muted.opacity(0.8))
                if let error {
                    Text(error)
                        .font(style.font(11.5))
                        .foregroundStyle(style.warning)
                }
            }
        }
        .shadow(color: style.accent.opacity(style.theme.glow * 0.5), radius: style.glowRadius)
    }

    /// То, что открывает развёртка: приветствие, а не полосы-заглушки.
    private var revealed: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(welcome.title)
                    .font(style.font(12)).foregroundStyle(style.muted)
                Spacer()
                Text(strings("lock.unlocked").uppercased())
                    .font(style.font(11)).tracking(2).foregroundStyle(style.bright)
            }
            Rule().padding(.top, 8).padding(.bottom, 18)

            Text(welcome.greeting)
                .font(style.font(17))
                .foregroundStyle(style.bright)
                .padding(.bottom, 12)

            ForEach(Array(welcome.lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(style.font(13))
                    .foregroundStyle(line.hasPrefix("  ") ? style.text.opacity(0.8) : style.text)
            }

            Spacer()

            Text(welcome.footer)
                .font(style.font(11.5))
                .foregroundStyle(style.muted)
            Text(strings("lock.vault").uppercased())
                .font(style.font(10.5)).tracking(1.6).foregroundStyle(style.muted)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Choreography

    private func boot() {
        phase = .waiting
    }

    /// Reading is slow, the release is fast: the snap only exists because of
    /// the contrast between them.
    private func begin() {
        guard phase == .waiting else { return }
        phase = .reading
        withAnimation(.easeInOut(duration: 1.5)) { arc = 1 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard phase == .reading else { return }
            phase = .opening

            withAnimation(.easeOut(duration: 0.12)) { flash = 0.9 }
            withAnimation(.easeIn(duration: 0.25).delay(0.1)) { flash = 0 }

            // Anticipation, then the collapse into a line.
            withAnimation(.easeInOut(duration: 0.12)) { glyphScale = CGSize(width: 0.88, height: 0.88) }
            withAnimation(.easeIn(duration: 0.18).delay(0.12)) {
                glyphScale = CGSize(width: 1.5, height: 0.04)
                glyphOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.14).delay(0.28)) { lineOpacity = 1 }

            try? await Task.sleep(for: .milliseconds(440))
            // The CRT sweep, with the overshoot a real tube had.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { sweep = 1 }
            withAnimation(.easeOut(duration: 0.2).delay(0.2)) { lineOpacity = 0 }

            try? await Task.sleep(for: .milliseconds(620))
            phase = .open
            await onUnlock()
        }
    }

    /// ↑↑↓↓←→←→BA — питомец делает сальто. Стоит одного поворота.
    private func konamiKey(_ key: KonamiWatcher.Key) {
        var watcher = konami
        if watcher.accept(key) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { somersault.toggle() }
        }
        konami = watcher
    }
}

/// Отпечаток пальца: подушечка с петлевым узором внутри.
///
/// Контур здесь несёт смысл, а не украшает. Без него концентрические дуги
/// читаются как мишень; с ним — сразу как палец. Узор намеренно асимметричен:
/// ядро смещено влево, часть гребней разорвана, слева внизу стоит дельта —
/// у настоящих отпечатков нет симметрии, и глаз это замечает даже мельком.
///
/// Геометрия описана в клетке 100×100 и масштабируется под кадр, поэтому глиф
/// одинаково чист и в 84 пунктах на экране входа, и в мелкой иконке.
struct Fingerprint: Shape {
    /// Полуширина подушечки на уровне ядра: по ней обрезаются хвосты гребней,
    /// чтобы ни один не вылез за контур.
    private static let padHalfWidth = 34.0
    private static let core = (x: 47.0, y: 54.0)
    private static let radii = [5.0, 11.0, 17.0, 23.0, 29.0]

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 100
        let origin = CGPoint(
            x: rect.midX - 50 * unit,
            y: rect.midY - 50 * unit
        )
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }

        var path = Path()
        addOutline(to: &path, place: place)
        for (index, radius) in Self.radii.enumerated() {
            addRidge(radius: radius, index: index, to: &path, place: place)
        }
        addDelta(to: &path, place: place)
        return path
    }

    /// Силуэт подушечки: шире вверху, сужается книзу.
    private func addOutline(to path: inout Path, place: (Double, Double) -> CGPoint) {
        path.move(to: place(50, 5))
        path.addCurve(to: place(86, 48), control1: place(71, 5), control2: place(86, 23))
        path.addCurve(to: place(50, 96), control1: place(86, 76), control2: place(70, 96))
        path.addCurve(to: place(14, 48), control1: place(30, 96), control2: place(14, 76))
        path.addCurve(to: place(50, 5), control1: place(14, 23), control2: place(29, 5))
    }

    /// Один гребень: арка над ядром и два хвоста вниз, обрезанных контуром.
    private func addRidge(
        radius: Double, index: Int,
        to path: inout Path, place: (Double, Double) -> CGPoint
    ) {
        let core = Self.core
        // Гребни слегка вытянуты по вертикали — так узор перестаёт быть циркульным.
        let height = radius * 1.14
        let left = core.x - radius
        let right = core.x + radius
        // Хвост тем короче, чем шире гребень: иначе он пробьёт контур.
        let reach = 1 - min(1, radius / Self.padHalfWidth) * min(1, radius / Self.padHalfWidth)
        let tail = core.y + 8 + reach.squareRoot() * 30

        path.move(to: place(left, tail))
        path.addLine(to: place(left, core.y))
        path.addCurve(
            to: place(right, core.y),
            control1: place(left, core.y - height * 1.34),
            control2: place(right, core.y - height * 1.34)
        )
        // Каждый второй гребень с разрывом — как на настоящем пальце.
        if index % 2 == 1 {
            path.addLine(to: place(right, core.y + 10))
            path.move(to: place(right, core.y + 20))
        }
        path.addLine(to: place(right, tail))
    }

    /// Дельта — точка схождения узора слева внизу.
    private func addDelta(to path: inout Path, place: (Double, Double) -> CGPoint) {
        path.move(to: place(22, 72))
        path.addLine(to: place(29, 66))
        path.move(to: place(22, 79))
        path.addLine(to: place(30, 73))
    }
}
