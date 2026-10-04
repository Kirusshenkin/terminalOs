public import Foundation
import PhosphorCore
import SSHKit

/// Проверяет релизы и ставит обновление.
///
/// Сеть и файлы — в акторе, как и остальное, что может ждать. Ставится только
/// то, что прошло три проверки: подпись манифеста, размер и sha256 архива,
/// подпись кода распакованного приложения.
actor Updater {
    enum Failure: Error, Equatable {
        case network
        case badSignature
        case corrupted
        case install(String)
    }

    private static let manifestURL = URL(
        string: "https://github.com/Kirusshenkin/terminalOs/releases/latest/download/latest.json")!
    private var etag: String?

    /// Свежий манифест, если вышло что-то новее запущенного. nil — новее нет
    /// или GitHub ответил «не изменилось».
    func check(currentBuild: Int) async throws(Failure) -> UpdateManifest? {
        var request = URLRequest(url: Self.manifestURL)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { throw .network }
        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200 else { throw .network }
        // Релиз без подписи (выпущенный до неё) — нечего предлагать, а не
        // подмена: тревогу поднимает только подпись, которая есть и не сошлась.
        guard
            let (signature, signatureResponse) = try? await URLSession.shared.data(
                from: Self.manifestURL.appendingPathExtension("sig"))
        else { throw .network }
        guard (signatureResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let manifest: UpdateManifest
        do {
            manifest = try UpdateManifest.verified(data, signature: signature)
        } catch {
            throw .badSignature
        }
        // Запоминаем ETag только у проверенного ответа: иначе подменённый
        // манифест «застрял» бы как неизменившийся.
        etag = http.value(forHTTPHeaderField: "ETag")
        return manifest.isNewer(thanBuild: currentBuild) ? manifest : nil
    }

    /// Скачивает, проверяет и кладёт новое приложение на место текущего.
    /// Возвращает путь, который надо открыть после выхода.
    func install(_ manifest: UpdateManifest, over current: URL) async throws(Failure) -> URL {
        guard let (archive, _) = try? await URLSession.shared.data(from: manifest.url) else {
            throw .network
        }
        guard manifest.matches(archive) else { throw .corrupted }

        let manager = FileManager.default
        let stage = manager.temporaryDirectory.appendingPathComponent("phosphor-update-\(UUID().uuidString)")
        defer {
            // Черновик обновления: если не удалился, его уберёт система.
            try? manager.removeItem(at: stage)
        }
        do {
            try manager.createDirectory(at: stage, withIntermediateDirectories: true)
            let zip = stage.appendingPathComponent("Phosphor.zip")
            try archive.write(to: zip)
            try await run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path])
            let fresh = stage.appendingPathComponent("Phosphor.app")
            // Подпись кода после распаковки: битый бандл не должен заменить
            // рабочий — иначе человек остаётся без приложения вовсе.
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path])
            // replaceItemAt меняет бандл целиком и сохраняет старый, если
            // что-то пошло не так посередине.
            _ = try manager.replaceItemAt(current, withItemAt: fresh)
            return current
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .install(error.localizedDescription)
        }
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        let result = try await Subprocess.run(executable: executable, arguments: arguments, timeout: .seconds(120))
        guard result.status == 0 else {
            throw Failure.install(String(result.stderr.prefix(200)))
        }
    }

    /// Открывает приложение заново, когда текущий процесс завершится.
    ///
    /// Ждёт факта — исчезновения процесса, — а не фиксированной паузы; чтобы
    /// не повиснуть навсегда, ожидание ограничено полуминутой.
    nonisolated static func relaunch(_ app: URL, after pid: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; "
                + "/usr/bin/open \(Shell.quote(app.path))",
        ]
        try process.run()
    }
}
