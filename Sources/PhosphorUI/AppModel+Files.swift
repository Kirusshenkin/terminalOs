public import Foundation
public import SSHKit
public import SessionKit

/// Просмотр файлов на обеих сторонах.
@MainActor
extension AppModel {
    public var connectedHostName: String {
        book.hosts.first { $0.id == selectedHost }?.name ?? strings("files.server")
    }

    /// Читает обе панели. Локальная не зависит от подключения.
    public func loadFiles() async {
        loadLocal()
        await loadRemote()
    }

    func loadLocal() {
        let url = URL(fileURLWithPath: localPath)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            localFiles = []
            return
        }
        var files: [RemoteFile] = [parentEntry]
        for name in names where !name.hasPrefix(".") {
            let child = url.appendingPathComponent(name)
            let values = try? child.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            ])
            files.append(
                RemoteFile(
                    name: name,
                    permissions: values?.isDirectory == true ? "drwxr-xr-x" : "-rw-r--r--",
                    owner: NSUserName(),
                    size: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate,
                    isDirectory: values?.isDirectory ?? false,
                    isSymlink: false,
                    linkTarget: nil
                ))
        }
        localFiles = files.sorted { left, right in
            if left.name == ".." { return true }
            if right.name == ".." { return false }
            if left.isDirectory != right.isDirectory { return left.isDirectory }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private var parentEntry: RemoteFile {
        RemoteFile(
            name: "..", permissions: "drwxr-xr-x", owner: "", size: 0,
            modified: nil, isDirectory: true, isSymlink: false, linkTarget: nil
        )
    }

    func loadRemote() async {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }),
            let socket = sessionSocketPath
        else {
            remoteFiles = []
            return
        }
        let browser = FileBrowser(
            transport: SystemSSHTransport(host: host, reach: book.reach(for: host)),
            host: host, reach: book.reach(for: host), controlPath: socket
        )
        do {
            remoteFiles = try await browser.list(remotePath)
            filesError = nil
        } catch {
            filesError = "\(strings("files.cannotRead")) \(remotePath): \(strings.describe(error))"
            remoteFiles = []
        }
    }

    /// Заходит в папку локально. Файлы не открываем: это не файловый менеджер.
    public func openLocal(_ file: RemoteFile) {
        guard file.isDirectory else { return }
        localPath =
            file.name == ".."
            ? (localPath as NSString).deletingLastPathComponent
            : (localPath as NSString).appendingPathComponent(file.name)
        if localPath.isEmpty { localPath = "/" }
        loadLocal()
    }

    // MARK: - Передача

    /// Скачивает выделенное с сервера в текущую локальную папку.
    ///
    /// Направление не угадывается по фокусу: строка на удалённой панели едет
    /// сюда, строка на локальной — туда. Так понятно до нажатия, что случится.
    public func download(_ file: RemoteFile) async {
        guard file.name != ".." else { return }
        let destination = (localPath as NSString).appendingPathComponent(file.name)
        await begin(
            FileTransfer(file: file, direction: .download, destination: destination),
            occupied: FileManager.default.fileExists(atPath: destination))
    }

    /// Заливает выделенное на сервер в текущую удалённую папку.
    public func upload(_ file: RemoteFile) async {
        guard file.name != ".." else { return }
        let destination = (remotePath as NSString).appendingPathComponent(file.name)
        await begin(
            FileTransfer(file: file, direction: .upload, destination: destination),
            occupied: remoteFiles.contains { $0.name == file.name })
    }

    /// Заливает то, что принесли из Finder: перетаскивание — это и есть загрузка.
    public func upload(dropped url: URL) async {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let file = RemoteFile(
            name: url.lastPathComponent,
            permissions: values?.isDirectory == true ? "drwxr-xr-x" : "-rw-r--r--",
            owner: NSUserName(),
            size: Int64(values?.fileSize ?? 0),
            modified: nil,
            isDirectory: values?.isDirectory ?? false,
            isSymlink: false,
            linkTarget: nil
        )
        // Путь берём от источника, а не от локальной панели: принесённый файл
        // может лежать где угодно.
        let destination = (remotePath as NSString).appendingPathComponent(file.name)
        await begin(
            FileTransfer(file: file, direction: .upload, destination: destination),
            occupied: remoteFiles.contains { $0.name == file.name },
            source: url)
    }

    /// Отправляет передачу в работу или сперва спрашивает про замену.
    private func begin(_ request: FileTransfer, occupied: Bool, source: URL? = nil) async {
        guard transfer == nil else { return }
        droppedSource = source
        if occupied {
            pendingOverwrite = request
            return
        }
        await run(request)
    }

    /// Подтверждённая замена: то же самое, но уже без вопроса.
    public func confirmOverwrite() async {
        guard let request = pendingOverwrite else { return }
        pendingOverwrite = nil
        await run(request)
    }

    public func cancelOverwrite() {
        pendingOverwrite = nil
        droppedSource = nil
    }

    private func run(_ request: FileTransfer) async {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }),
            let socket = sessionSocketPath
        else {
            filesError = strings("files.noLink")
            return
        }
        let browser = FileBrowser(
            transport: SystemSSHTransport(host: host, reach: book.reach(for: host)),
            host: host, reach: book.reach(for: host), controlPath: socket
        )
        transfer = request
        filesError = nil
        defer {
            transfer = nil
            droppedSource = nil
        }
        do {
            switch request.direction {
            case .download:
                try await browser.download(
                    remote: (remotePath as NSString).appendingPathComponent(request.file.name),
                    to: URL(fileURLWithPath: request.destination),
                    directory: request.file.isDirectory)
                loadLocal()
            case .upload:
                let source =
                    droppedSource
                    ?? URL(
                        fileURLWithPath:
                            (localPath as NSString).appendingPathComponent(request.file.name))
                try await browser.upload(
                    local: source, to: request.destination,
                    directory: request.file.isDirectory)
                await loadRemote()
            }
        } catch {
            // Причина у scp лежит в stderr и обычно называет виновника прямо:
            // «Permission denied», «No space left». Прятать её не за чем.
            filesError = "\(request.file.name): \(reason(error))"
        }
    }

    /// Текст ошибки без внутренностей типа: человеку нужна причина, а не
    /// имя перечисления.
    private func reason(_ error: any Error) -> String {
        guard case TransportError.commandFailed(_, let stderr) = error else {
            return error.localizedDescription
        }
        let cleaned = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? error.localizedDescription : cleaned
    }

    public func openRemote(_ file: RemoteFile) async {
        guard file.isDirectory else { return }
        remotePath =
            file.name == ".."
            ? ((remotePath as NSString).deletingLastPathComponent.isEmpty
                ? "/" : (remotePath as NSString).deletingLastPathComponent)
            : (remotePath as NSString).appendingPathComponent(file.name)
        await loadRemote()
    }
}
