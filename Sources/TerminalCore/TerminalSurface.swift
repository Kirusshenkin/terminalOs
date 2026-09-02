public import AppKit
public import HostsKit
public import PhosphorCore
public import SSHKit
public import SwiftTerm
public import ThemeKit

/// A terminal view that runs a local shell.
///
/// SwiftTerm does the VT100 work; this type owns the two things that are ours:
/// the palette comes from the app's theme, and every byte from the far end goes
/// through `AnsiGuard` first.
public final class TerminalSurface: LocalProcessTerminalView {
    /// Called when the stream asked for something that needs a person to decide.
    public var onGuardRequest: ((AnsiGuard.Request) -> Void)?

    private var guardian = AnsiGuard()

    /// Paints the emulator with a theme.
    public func apply(theme: Theme) {
        let colours = theme.ansi.map { rgba in
            SwiftTerm.Color(
                red: UInt16(rgba.red * 65_535),
                green: UInt16(rgba.green * 65_535),
                blue: UInt16(rgba.blue * 65_535)
            )
        }
        installColors(colours)
        nativeForegroundColor = NSColor(theme.foreground)
        nativeBackgroundColor = NSColor(theme.background)
        caretColor = NSColor(theme.cursor)
        selectedTextBackgroundColor = NSColor(theme.selection)
        font = Self.font(size: 13)
    }

    /// Шрифт терминала: основной плюс запасной для иконок.
    ///
    /// `ls --icons`, powerline-разделители и статусные строки рисуются кодами из
    /// приватной области Unicode. В обычном шрифте их нет, и вместо иконки
    /// остаётся пустой прямоугольник. Каскад отправляет CoreText в Symbols Nerd
    /// Font ровно за теми кодами, которых нет в основном шрифте, — метрики и
    /// вид текста при этом не меняются.
    static func font(size: CGFloat) -> NSFont {
        let base =
            NSFont(name: "IBMPlexMono", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let symbols = NSFontDescriptor(fontAttributes: [.family: symbolsFamily])
        let cascading = base.fontDescriptor.addingAttributes([.cascadeList: [symbols]])
        return NSFont(descriptor: cascading, size: size) ?? base
    }

    /// Начертание лежит в бандле и регистрируется через `ATSApplicationFontsPath`.
    static let symbolsFamily = "Symbols Nerd Font Mono"

    /// Feeds bytes from a server through the guard before the emulator sees them.
    ///
    /// Everything the far end sends is untrusted: a log line can carry an
    /// `OSC 52` that plants a command in the clipboard, or a report request that
    /// makes the terminal answer with text the server chose. Neither reaches the
    /// emulator.
    public func feedGuarded(_ bytes: [UInt8]) {
        let output = guardian.filter(bytes)
        for request in output.requests { onGuardRequest?(request) }
        if !output.bytes.isEmpty { feed(byteArray: ArraySlice(output.bytes)) }
    }

    /// Открывает интерактивный шелл на сервере.
    ///
    /// Идёт тем же `ssh` и по тому же управляющему сокету, что и остальные
    /// команды: одно соединение, один логин, одно место, где видно обрыв.
    public func startRemoteShell(host: ServerHost, reach: Reach, controlPath: String) {
        startProcess(
            executable: SSHInvocation.executable,
            args: SSHInvocation.shellArguments(host: host, reach: reach, controlPath: controlPath),
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color")
        )
    }

    /// Starts a login shell in the user's home directory.
    public func startLocalShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = (shell as NSString).lastPathComponent
        startProcess(
            executable: shell,
            args: ["-l"],
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
            execName: "-\(name)"
        )
    }
}

extension NSColor {
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}
