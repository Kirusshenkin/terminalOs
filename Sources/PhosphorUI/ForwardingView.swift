public import SessionKit
public import SwiftUI

/// Проброс портов: список, состояние, добавление.
public struct ForwardingView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    @State private var direction = PortForward.Direction.local
    @State private var listenPort = ""
    @State private var targetHost = "127.0.0.1"
    @State private var targetPort = ""

    public init(model: AppModel) { self.model = model }

    private var isValid: Bool {
        (Int(listenPort).map { (1...65_535).contains($0) } ?? false)
            && (Int(targetPort).map { (1...65_535).contains($0) } ?? false)
            && model.selectedHost != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(strings("fwd.title")).font(style.font(15)).foregroundStyle(style.bright)
                Text(
                    model.selectedHost == nil
                        ? strings("fwd.noHost")
                        : model.connectedHostName
                )
                .font(style.font(12)).foregroundStyle(style.muted)
            }

            editor
            Rule()

            if model.forwards.isEmpty {
                Text(strings("fwd.empty"))
                    .font(style.font(12)).foregroundStyle(style.muted)
            }
            ForEach(model.forwards) { forward in row(forward) }

            if let error = model.forwardError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
            }
            Spacer(minLength: 0)

            Text(
                strings("fwd.note")
            )
            .font(style.font(11)).foregroundStyle(style.muted)
        }
    }

    private var editor: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label2(strings("fwd.direction"))
                HStack(spacing: 6) {
                    ForEach(PortForward.Direction.allCases, id: \.self) { item in
                        Button {
                            direction = item
                        } label: {
                            Text(item.title)
                                .font(style.font(11))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .foregroundStyle(direction == item ? style.background : style.muted)
                                .background(direction == item ? style.accent : .clear)
                                .overlay(
                                    Rectangle().stroke(
                                        direction == item ? style.accent : style.text.opacity(0.25),
                                        lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            field(strings("fwd.localPort"), text: $listenPort).frame(width: 110)
            field(strings("fwd.remoteHost"), text: $targetHost).frame(width: 150)
            field(strings("fwd.remotePort"), text: $targetPort).frame(width: 110)
            PhButton(strings("common.add"), kind: .primary) {
                model.addForward(
                    direction: direction,
                    listenPort: Int(listenPort) ?? 0,
                    targetHost: targetHost,
                    targetPort: Int(targetPort) ?? 0
                )
                listenPort = ""
                targetPort = ""
            }
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.4)
            Spacer()
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(title)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(style.font(12.5))
                .foregroundStyle(style.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
        }
    }

    private func row(_ forward: PortForward) -> some View {
        let running = model.activeForwards.contains(forward.id)
        return HStack(spacing: 12) {
            Text(running ? "●" : "○")
                .foregroundStyle(running ? style.accent : style.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(forward.summary).foregroundStyle(style.text)
                Text(forward.direction.title).font(style.font(10.5)).foregroundStyle(style.muted)
            }
            Spacer()
            Toggle(
                isOn: Binding(
                    get: { forward.autoStart },
                    set: { model.setAutoStart($0, for: forward) }
                )
            ) {
                Text(strings("fwd.onConnect")).font(style.font(10.5)).foregroundStyle(style.muted)
            }
            .toggleStyle(.checkbox)
            PhButton(running ? strings("fwd.down") : strings("fwd.up")) {
                Task { await model.toggleForward(forward) }
            }
            PhButton(strings("common.delete"), kind: .danger) { model.removeForward(forward) }
        }
        .font(style.font(12))
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(style.rule.opacity(0.5)).frame(height: 1) }
    }
}
