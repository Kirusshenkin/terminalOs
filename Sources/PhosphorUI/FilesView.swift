public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Файлы: локальная панель слева, сервер справа.
public struct FilesView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 22) {
                panel(
                    title: strings("files.local"),
                    path: model.localPath,
                    files: model.localFiles,
                    onOpen: { model.openLocal($0) },
                    action: model.session == nil ? nil : .upload
                )
                Rectangle().fill(style.rule).frame(width: 1)
                remotePanel
            }
            if let transfer = model.transfer {
                // Прогресса у scp нет, поэтому не выдумываем полосу: видно, что
                // именно едет и в какую сторону, и что работа идёт.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(
                        "\(strings(transfer.direction == .download ? "files.downloading" : "files.uploading")) \(transfer.file.name)"
                    )
                    .font(style.font(11.5)).foregroundStyle(style.bright)
                }
            }
            if let error = model.filesError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hint
        }
        .task { await model.loadFiles() }
    }

    @ViewBuilder private var remotePanel: some View {
        if model.session == nil {
            VStack(spacing: 12) {
                Text(strings("files.noLink"))
                    .font(style.font(14)).foregroundStyle(style.muted)
                Text(strings("files.pickOnHosts"))
                    .font(style.font(11.5)).foregroundStyle(style.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            panel(
                title: "\(model.connectedHostName) · \(strings("files.sameSSH"))",
                path: model.remotePath,
                files: model.remoteFiles,
                onOpen: { file in Task { await model.openRemote(file) } },
                action: .download
            )
            // Принесённое из Finder едет на сервер: перетаскивание — это и есть
            // загрузка, как и обещано в плане.
            .dropDestination(for: URL.self) { urls, _ in
                guard let first = urls.first else { return false }
                Task { await model.upload(dropped: first) }
                return true
            }
        }
    }

    /// Что делает кнопка на строке этой панели. nil — сервера нет, и переносить
    /// некуда.
    private enum RowAction {
        case download
        case upload

        var symbol: String {
            switch self {
            case .download: "arrow.left"
            case .upload: "arrow.right"
            }
        }
        var titleKey: String {
            switch self {
            case .download: "files.download"
            case .upload: "files.upload"
            }
        }
    }

    private func panel(
        title: String, path: String, files: [RemoteFile],
        onOpen: @escaping (RemoteFile) -> Void,
        action: RowAction?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(title)
            Text(path).font(style.font(12)).foregroundStyle(style.muted).lineLimit(1)
            columns
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        fileRow(file, onOpen: onOpen, action: action)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columns: some View {
        HStack(spacing: 8) {
            Label2(strings("host.name")).frame(maxWidth: .infinity, alignment: .leading)
            Label2(strings("files.modified")).frame(width: 120, alignment: .leading)
            Label2(strings("files.size")).frame(width: 80, alignment: .trailing)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func fileRow(
        _ file: RemoteFile, onOpen: @escaping (RemoteFile) -> Void, action: RowAction?
    ) -> some View {
        HStack(spacing: 6) {
            nameButton(file, onOpen: onOpen)
            if let action, file.name != ".." {
                transferButton(file, action: action)
            }
        }
    }

    /// Кнопка переноса стоит на самой строке: путь до файла уже выбран тем, что
    /// человек на него смотрит, и спрашивать его ещё раз панелью выбора незачем.
    private func transferButton(_ file: RemoteFile, action: RowAction) -> some View {
        Button {
            Task {
                switch action {
                case .download: await model.download(file)
                case .upload: await model.upload(file)
                }
            }
        } label: {
            Image(systemName: action.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.muted)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .help(strings(action.titleKey))
        .disabled(model.transfer != nil)
    }

    private func nameButton(
        _ file: RemoteFile, onOpen: @escaping (RemoteFile) -> Void
    ) -> some View {
        Button {
            onOpen(file)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(file.isDirectory ? "▸" : " ").foregroundStyle(style.muted)
                        Text(file.name)
                            .foregroundStyle(file.isDirectory ? style.bright : style.text)
                        if let target = file.linkTarget {
                            Text("→ \(target)")
                                .font(style.font(10.5)).foregroundStyle(style.muted)
                        }
                    }
                    Text("\(file.permissions)  \(file.owner)")
                        .font(style.font(10)).foregroundStyle(style.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(file.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "—")
                    .font(style.font(11)).foregroundStyle(style.muted)
                    .frame(width: 120, alignment: .leading)

                Text(file.isDirectory ? "—" : ByteFormat.size(file.size))
                    .font(style.font(11)).foregroundStyle(style.muted)
                    .frame(width: 80, alignment: .trailing)
            }
            .font(style.font(12))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hint: some View {
        Text(strings("files.note"))
            .font(style.font(11))
            .foregroundStyle(style.muted)
    }
}
