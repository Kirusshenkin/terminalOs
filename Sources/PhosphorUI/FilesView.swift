public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Файлы: локальная панель слева, сервер справа.
public struct FilesView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 22) {
                panel(
                    title: "локально",
                    path: model.localPath,
                    files: model.localFiles,
                    onOpen: { model.openLocal($0) }
                )
                Rectangle().fill(style.rule).frame(width: 1)
                remotePanel
            }
            if let error = model.filesError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
            }
            hint
        }
        .task { await model.loadFiles() }
    }

    @ViewBuilder private var remotePanel: some View {
        if model.session == nil {
            VStack(spacing: 12) {
                Text("нет подключения")
                    .font(style.font(14)).foregroundStyle(style.muted)
                Text("выбери хост на вкладке «хосты»")
                    .font(style.font(11.5)).foregroundStyle(style.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            panel(
                title: "\(model.connectedHostName) · то же ssh-соединение",
                path: model.remotePath,
                files: model.remoteFiles,
                onOpen: { file in Task { await model.openRemote(file) } }
            )
        }
    }

    private func panel(
        title: String, path: String, files: [RemoteFile],
        onOpen: @escaping (RemoteFile) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(title)
            Text(path).font(style.font(12)).foregroundStyle(style.muted).lineLimit(1)
            HStack(spacing: 8) {
                Label2("имя").frame(maxWidth: .infinity, alignment: .leading)
                Label2("изменён").frame(width: 120, alignment: .leading)
                Label2("размер").frame(width: 80, alignment: .trailing)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files) { file in
                        Button {
                            onOpen(file)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(file.isDirectory ? "▸" : " ")
                                            .foregroundStyle(style.muted)
                                        Text(file.name)
                                            .foregroundStyle(file.isDirectory ? style.bright : style.text)
                                        if let target = file.linkTarget {
                                            Text("→ \(target)")
                                                .font(style.font(10.5))
                                                .foregroundStyle(style.muted)
                                        }
                                    }
                                    Text("\(file.permissions)  \(file.owner)")
                                        .font(style.font(10)).foregroundStyle(style.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(
                                    file.modified.map {
                                        $0.formatted(date: .numeric, time: .shortened)
                                    } ?? "—"
                                )
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
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: some View {
        Text(
            "файлы идут по тому же соединению, что и терминал: отдельного логина нет, "
                + "и через тот же прокси или бастион"
        )
        .font(style.font(11))
        .foregroundStyle(style.muted)
    }
}
