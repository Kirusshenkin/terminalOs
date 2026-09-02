import Darwin
public import Foundation
import Security

/// Слушает локальный сокет и отдаёт инструменты шиму.
///
/// Сетевого доступа нет намеренно: единственный вход — файл в Application
/// Support с правами 0600, и каждый запрос обязан принести токен, который
/// приложение сгенерировало при запуске. Иначе любой процесс на машине,
/// дотянувшийся до сокета, управлял бы твоими серверами через нас.
public actor SocketServer {
    public enum ServerError: Error, Equatable {
        case cannotBind(String)
    }

    private let path: String
    private let tokenPath: String
    private var descriptor: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private(set) var token = ""

    /// Обработчик запроса. Возвращает ответ, который уйдёт шиму.
    private let handle: @Sendable (BridgeRequest) async -> BridgeResponse

    public init(
        path: String = BridgeLocation.socketPath(),
        tokenPath: String = BridgeLocation.tokenPath(),
        handle: @escaping @Sendable (BridgeRequest) async -> BridgeResponse
    ) {
        self.path = path
        self.tokenPath = tokenPath
        self.handle = handle
    }

    public var socketPath: String { path }

    /// Поднимает сокет и начинает принимать соединения.
    public func start() throws {
        try stop()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        unlink(path)

        token = Self.freshToken()
        try Data(token.utf8).write(to: URL(fileURLWithPath: tokenPath), options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: tokenPath)

        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ServerError.cannotBind("socket") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maximum = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maximum else { throw ServerError.cannotBind("путь слишком длинный") }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source, maximum - 1)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, size) }
        }
        guard bound == 0 else { throw ServerError.cannotBind("bind: \(errno)") }
        // Права ставим сразу после bind: между bind и chmod окна быть не должно.
        chmod(path, 0o600)
        guard listen(descriptor, 4) == 0 else { throw ServerError.cannotBind("listen") }

        let fd = descriptor
        acceptTask = Task { [weak self] in
            while !Task.isCancelled {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                guard let self else { close(client); break }
                await self.serve(client)
            }
        }
    }

    public func stop() throws {
        acceptTask?.cancel()
        acceptTask = nil
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
        unlink(path)
        try? FileManager.default.removeItem(atPath: tokenPath)
    }

    /// Обслуживает одно соединение: строка запроса — строка ответа.
    private func serve(_ client: Int32) async {
        defer { close(client) }
        guard Self.peerIsSameUser(client) else { return }

        guard let line = Self.readLine(from: client),
            let data = line.data(using: .utf8),
            let request = try? JSONDecoder().decode(BridgeRequest.self, from: data)
        else { return }

        // Сравнение постоянного времени: токен короткий, но привычка полезная.
        guard Self.constantTimeEquals(request.token, token) else {
            Self.write(BridgeResponse(ok: false, text: "неверный токен"), to: client)
            return
        }
        let response = await handle(request)
        Self.write(response, to: client)
    }

    /// Проверяет, что на том конце тот же пользователь.
    ///
    /// Права на файл сокета уже это гарантируют, но проверка стоит один вызов и
    /// защищает от случаев, когда права кто-то поменял.
    private static func peerIsSameUser(_ client: Int32) -> Bool {
        var uid = uid_t()
        var gid = gid_t()
        guard getpeereid(client, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    private static func readLine(from client: Int32) -> String? {
        var buffer = [UInt8]()
        var byte: UInt8 = 0
        while read(client, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 1 << 20 { return nil }
        }
        return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    }

    private static func write(_ response: BridgeResponse, to client: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(client, raw.baseAddress?.advanced(by: offset), raw.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    static func freshToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8)
        let b = Array(right.utf8)
        guard a.count == b.count, !a.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}
