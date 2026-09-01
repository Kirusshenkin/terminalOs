public import Foundation
public import SSHKit
public import SessionKit

/// Просмотр файлов на обеих сторонах.
@MainActor
extension AppModel {
    public var connectedHostName: String {
        book.hosts.first { $0.id == selectedHost }?.name ?? "сервер"
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
            filesError = "не удалось прочитать \(remotePath): \(error)"
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
