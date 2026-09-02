import Darwin
import Foundation
import MCPBridge

/// Шим между MCP-клиентом и приложением.
///
/// Говорит по stdio на JSON-RPC, как ждёт клиент, и передаёт запросы Phosphor
/// через локальный сокет. Сам ничего не решает и ничего не умеет: вся политика,
/// подтверждения и журнал живут в приложении, где есть человек, которого можно
/// спросить.
///
/// Весит копейки намеренно — он запускается клиентом, а не пользователем.
struct Shim {
    static func main() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard let method = message["method"] as? String else { continue }
            let id = message["id"]

            switch method {
            case "initialize":
                reply(
                    id: id,
                    result: [
                        "protocolVersion": "2024-11-05",
                        "capabilities": ["tools": [String: Any]()],
                        "serverInfo": ["name": "phosphor", "version": "1.0"],
                    ])
            case "notifications/initialized":
                continue
            case "tools/list":
                reply(id: id, result: ["tools": toolSchemas()])
            case "tools/call":
                handleCall(message, id: id)
            default:
                reply(id: id, error: "неизвестный метод: \(method)")
            }
        }
    }

    // MARK: - Инструменты

    private static func toolSchemas() -> [[String: Any]] {
        BridgeLocation.descriptions().map { tool in
            var properties: [String: Any] = [:]
            for name in tool.arguments {
                properties[name] = ["type": "string", "description": hint(for: name)]
            }
            return [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": [
                    "type": "object",
                    "properties": properties,
                    "required": tool.arguments.filter { $0 == "host" },
                ],
            ]
        }
    }

    private static func hint(for argument: String) -> String {
        switch argument {
        case "host": "идентификатор хоста из list_hosts"
        case "command": "команда для выполнения на сервере"
        case "container": "имя или идентификатор контейнера"
        case "action": "start, stop, restart, pause, unpause, kill или remove"
        case "tail": "сколько последних строк вернуть"
        case "operation": "add или remove"
        case "key": "строка ключа в формате authorized_keys"
        default: argument
        }
    }

    private static func handleCall(_ message: [String: Any], id: Any?) {
        let parameters = message["params"] as? [String: Any] ?? [:]
        guard let name = parameters["name"] as? String else {
            reply(id: id, error: "не указано имя инструмента")
            return
        }
        var arguments: [String: String] = [:]
        for (key, value) in parameters["arguments"] as? [String: Any] ?? [:] {
            arguments[key] = String(describing: value)
        }

        guard
            let token = try? String(
                contentsOfFile: BridgeLocation.tokenPath(), encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            reply(id: id, result: content("Phosphor не запущен — открой приложение", isError: true))
            return
        }

        let request = BridgeRequest(token: token, method: "call", tool: name, arguments: arguments)
        guard let response = send(request) else {
            reply(id: id, result: content("Phosphor не отвечает", isError: true))
            return
        }
        reply(id: id, result: content(response.text, isError: !response.ok))
    }

    private static func content(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    // MARK: - Сокет

    private static func send(_ request: BridgeRequest) -> BridgeResponse? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = BridgeLocation.socketPath()
        let maximum = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maximum else { return nil }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source, maximum - 1)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, size)
            }
        }
        guard connected == 0, var payload = try? JSONEncoder().encode(request) else { return nil }
        payload.append(0x0A)
        _ = payload.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }

        var buffer = [UInt8]()
        var byte: UInt8 = 0
        while read(descriptor, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 1 << 22 { break }
        }
        return try? JSONDecoder().decode(BridgeResponse.self, from: Data(buffer))
    }

    // MARK: - Ответы

    private static func reply(id: Any?, result: [String: Any]) {
        emit(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private static func reply(id: Any?, error: String) {
        emit([
            "jsonrpc": "2.0", "id": id ?? NSNull(),
            "error": ["code": -32_601, "message": error],
        ])
    }

    private static func emit(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
            let text = String(data: data, encoding: .utf8)
        else { return }
        print(text)
        fflush(stdout)
    }
}

Shim.main()
