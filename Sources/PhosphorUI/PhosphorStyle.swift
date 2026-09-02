public import AppKit
public import SwiftUI
public import ThemeKit

public extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// Colours and metrics derived from the active theme.
///
/// Views read this instead of literals so switching a theme repaints everything
/// at once, and so a host's group can carry its own look.
public struct Style: Sendable {
    public var theme: Theme

    public init(theme: Theme = BuiltInThemes.phosphor) { self.theme = theme }

    public var background: Color { Color(theme.background) }
    public var text: Color { Color(theme.foreground) }
    public var bright: Color { Color(theme.ansi[15]) }
    public var dim: Color { Color(theme.ansi[8]).opacity(0.95) }
    public var muted: Color { Color(theme.ansi[2]) }
    public var accent: Color { Color(theme.ansi[10]) }
    public var warning: Color { Color(theme.ansi[11]) }
    public var danger: Color { Color(theme.ansi[9]) }
    public var cursor: Color { Color(theme.cursor) }

    public var rule: Color { text.opacity(0.22) }
    public var surface: Color { text.opacity(0.035) }

    /// Text glow strength, scaled by the theme's setting.
    public var glowRadius: CGFloat { 6 * theme.glow }

    /// Шрифт интерфейса.
    ///
    /// IBM Plex Mono лежит в бандле и регистрируется при запуске: полагаться на
    /// то, что он окажется в системе, нельзя, а системный SF Mono выглядит
    /// заметно иначе — и весь экран вместе с ним.
    public static let mono = "IBMPlexMono"

    public func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name =
            switch weight {
            case .semibold, .bold, .heavy, .black: "IBMPlexMono-SemiBold"
            case .medium: "IBMPlexMono-Medium"
            default: "IBMPlexMono"
            }
        guard NSFont(name: name, size: size) != nil else {
            // Шрифт не зарегистрировался — не рисовать же ничего.
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(name, size: size)
    }
}

private struct StyleKey: EnvironmentKey {
    static let defaultValue = Style()
}

public extension EnvironmentValues {
    var style: Style {
        get { self[StyleKey.self] }
        set { self[StyleKey.self] = newValue }
    }
}

/// The CRT surface every screen sits on: rounded glass, scanlines, vignette.
///
/// Scanlines and vignette are static gradients, not animations — they cost one
/// composite and nothing per frame.
public struct CRTFrame<Content: View>: View {
    @Environment(\.style) private var style
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        ZStack {
            style.background
            content
                .padding(26)
            if style.theme.scanlines > 0 {
                Canvas { context, size in
                    let opacity = 0.34 * style.theme.scanlines
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                            with: .color(.black.opacity(opacity))
                        )
                        y += 3
                    }
                }
                .allowsHitTesting(false)
            }
            if style.theme.vignette > 0 {
                RadialGradient(
                    colors: [.clear, .black.opacity(0.75 * style.theme.vignette)],
                    center: .center, startRadius: 220, endRadius: 640
                )
                .allowsHitTesting(false)
            }
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(14)
    }
}

/// A section label in the small-caps style used throughout.
public struct Label2: View {
    @Environment(\.style) private var style
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(style.font(10.5))
            .tracking(1.6)
            .foregroundStyle(style.muted)
    }
}

public struct Rule: View {
    @Environment(\.style) private var style
    public init() {}
    public var body: some View { Rectangle().fill(style.rule).frame(height: 1) }
}

/// Bordered action used for every command in the interface.
public struct PhButton: View {
    @Environment(\.style) private var style
    public enum Kind { case normal, primary, danger }

    private let title: String
    private let kind: Kind
    private let action: () -> Void

    public init(_ title: String, kind: Kind = .normal, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(style.font(10.5, weight: .medium))
                .tracking(1.2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .foregroundStyle(foreground)
                .background(fill)
                .overlay(Rectangle().stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch kind {
        case .normal: style.text
        case .primary: style.background
        case .danger: style.warning
        }
    }
    private var fill: Color { kind == .primary ? style.accent : .clear }
    private var border: Color {
        switch kind {
        case .normal: style.text.opacity(0.35)
        case .primary: style.accent
        case .danger: style.warning.opacity(0.55)
        }
    }
}
