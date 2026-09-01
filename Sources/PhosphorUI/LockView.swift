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
    private let onUnlock: () -> Void

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

    public init(strings: Strings, onUnlock: @escaping () -> Void) {
        self.strings = strings
        self.onUnlock = onUnlock
    }

    public var body: some View {
        Screen {
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
                Text(strings("lock.fallback"))
                    .font(style.font(11))
                    .foregroundStyle(style.muted.opacity(0.8))
            }
        }
        .shadow(color: style.accent.opacity(style.theme.glow * 0.5), radius: style.glowRadius)
    }

    /// What the sweep reveals: the shape of the interface behind the lock.
    private var revealed: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PHOSPHOR").font(style.font(11)).tracking(3).foregroundStyle(style.muted)
                Spacer()
                Text(strings("lock.unlocked").uppercased())
                    .font(style.font(11)).tracking(2).foregroundStyle(style.bright)
            }
            Rule()
            ForEach([0.76, 0.52, 0.64, 0.41, 0.7, 0.33, 0.58], id: \.self) { width in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(style.accent.opacity(0.3))
                        .frame(width: geometry.size.width * width, height: 6)
                }
                .frame(height: 6)
            }
            Spacer()
            Text(strings("lock.vault").uppercased())
                .font(style.font(10.5)).tracking(1.6).foregroundStyle(style.muted)
        }
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
            onUnlock()
        }
    }

    /// ↑↑↓↓←→←→BA — the pet turns a somersault. Costs one rotation.
    public mutating func konamiKey(_ key: KonamiWatcher.Key) {
        if konami.accept(key) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { somersault.toggle() }
        }
    }
}

/// A looping fingerprint: ridges with breaks and a core, drawn as arcs rather
/// than three fat curves.
struct Fingerprint: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.06)
        let radii: [CGFloat] = [0.05, 0.13, 0.21, 0.29, 0.37, 0.45]

        // Core loop.
        path.addArc(
            center: centre, radius: rect.width * 0.045,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)

        for (index, factor) in radii.enumerated() {
            let radius = rect.width * factor
            // A break in every other ridge, as a real print has.
            let start: CGFloat = index % 2 == 0 ? 180 : 200
            let end: CGFloat = index % 2 == 0 ? 0 : -20
            path.addArc(
                center: centre, radius: radius,
                startAngle: .degrees(Double(start)), endAngle: .degrees(Double(end)),
                clockwise: false)
            let tail = rect.height * (0.18 - CGFloat(index) * 0.015)
            path.move(to: CGPoint(x: centre.x - radius, y: centre.y))
            path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y + tail))
            path.move(to: CGPoint(x: centre.x + radius, y: centre.y))
            path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y + tail))
        }
        return path
    }
}
