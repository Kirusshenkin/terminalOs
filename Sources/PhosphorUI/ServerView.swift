public import SwiftUI

/// Everything that changes on the selected server and is not a terminal:
/// setup, who may log in, which ports are forwarded.
public struct ServerView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(title: model.strings("tab.server"), strings: model.strings, page: $model.serverPage)
            Rectangle().fill(style.rule).frame(width: 1)
            switch model.serverPage {
            case .setup: ProvisionView(model: model)
            // Читается при каждом заходе и смене сервера: чужой authorized_keys
            // на экране — худшее, что здесь может случиться.
            case .access: KeysView(model: model).task(id: model.selectedHost) { await model.loadKeys() }
            case .forwarding: ForwardingView(model: model)
            }
        }
    }
}

/// What this Mac holds for every server: its own key pairs and the host keys
/// it has learned to trust.
public struct KeyringView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(title: model.strings("tab.keys"), strings: model.strings, page: $model.keysPage)
            Rectangle().fill(style.rule).frame(width: 1)
            switch model.keysPage {
            case .mine: LocalKeysView(model: model)
            case .trusted: KnownHostsView(model: model).task { model.loadKnownHosts() }
            }
        }
    }
}
