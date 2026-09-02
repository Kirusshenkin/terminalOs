public import HostsKit
public import SwiftUI

/// Выбор сервера прямо на том экране, которому он нужен.
///
/// Docker, метрики и автонастройка без хоста показывать нечего. Раньше они
/// показывали витрину с придуманными числами — и человек видел работающий
/// сервер там, где не было даже соединения. Витрина убрана: пока сервер не
/// выбран, экран предлагает выбрать его из тех, что уже добавлены.
public struct HostPicker: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private let title: String
    private let note: String

    public init(model: AppModel, title: String, note: String) {
        self.model = model
        self.title = title
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(title)
            Text(note)
                .font(style.font(11))
                .foregroundStyle(style.muted)
                .padding(.bottom, 4)

            if model.book.hosts.isEmpty {
                Text("хостов пока нет")
                    .font(style.font(12))
                    .foregroundStyle(style.muted)
                Button {
                    model.screen = .hosts
                    model.isAddingHost = true
                } label: {
                    Text("+ добавить хост")
                        .font(style.font(11.5))
                        .foregroundStyle(style.bright)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                ForEach(model.book.hosts) { host in
                    row(host)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ host: ServerHost) -> some View {
        let isCurrent = model.selectedHost == host.id
        return Button {
            Task { await model.connect(to: host) }
        } label: {
            HStack(spacing: 8) {
                Text(isCurrent ? "▸" : " ")
                    .foregroundStyle(isCurrent ? style.bright : style.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                        .font(style.font(12.5))
                        .foregroundStyle(isCurrent ? style.bright : style.text)
                    Text("\(host.user)@\(host.address)")
                        .font(style.font(10.5))
                        .foregroundStyle(style.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
