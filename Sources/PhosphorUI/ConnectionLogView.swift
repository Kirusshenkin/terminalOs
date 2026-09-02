public import HostsKit
public import SwiftUI

/// История подключений: куда, когда и через что.
public struct ConnectionLogView: View {
    @Environment(\.style) private var style
    let model: AppModel
    private var strings: Strings { model.strings }

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(strings("clog.title")).font(style.font(15)).foregroundStyle(style.bright)
                Text("\(model.connectionEvents.count) \(strings("clog.records"))")
                    .font(style.font(12)).foregroundStyle(style.muted)
            }

            if model.connectionEvents.isEmpty {
                Text(strings("clog.empty")).font(style.font(12)).foregroundStyle(style.muted)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.connectionEvents) { event in
                        HStack(spacing: 12) {
                            Text(mark(event.kind))
                                .foregroundStyle(colour(event.kind))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 8) {
                                    Text(event.hostName).foregroundStyle(style.text)
                                    Text(event.address).foregroundStyle(style.muted)
                                }
                                Text(
                                    "\(event.title) · \(event.reach)"
                                        + (event.detail.map { " · \($0)" } ?? "")
                                )
                                .font(style.font(10.5)).foregroundStyle(style.muted)
                            }
                            Spacer()
                            Text(event.time.formatted(date: .abbreviated, time: .standard))
                                .font(style.font(11)).foregroundStyle(style.muted)
                        }
                        .font(style.font(12))
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                        }
                    }
                }
            }

            Text(
                strings("clog.note")
            )
            .font(style.font(11)).foregroundStyle(style.muted)
        }
    }

    private func mark(_ kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .connected: "→"
        case .disconnected: "←"
        case .failed: "✗"
        }
    }

    private func colour(_ kind: ConnectionEvent.Kind) -> Color {
        switch kind {
        case .connected: style.accent
        case .disconnected: style.muted
        case .failed: style.warning
        }
    }
}
