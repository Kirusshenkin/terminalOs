public import SwiftUI

/// The window: lock screen until unlocked, then the tabbed interface.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    public init() {}

    public var body: some View {
        Group {
            if model.isUnlocked {
                main
            } else {
                LockView(
                    strings: model.strings,
                    capability: model.gateCapability.summary,
                    error: model.unlockError
                ) {
                    await model.unlock()
                }
            }
        }
        .environment(\.style, model.style)
        .frame(minWidth: 1_060, minHeight: 680)
        // Опрос замирает, когда на окно никто не смотрит: терминал открыт весь
        // день, и фоновому окну незачем будить процессор.
        // Разрушающее действие называет контейнер по имени: «удалить» без
        // имени — это как раз то, о чём потом жалеют.
        .alert(item: $model.pendingAction) { pending in
            Alert(
                title: Text("\(pending.action.title) «\(pending.container.name)»?"),
                message: Text(pending.container.image),
                primaryButton: .destructive(Text(pending.action.title)) {
                    model.confirm(pending)
                },
                secondaryButton: .cancel(Text("отмена"))
            )
        }
        // Удаление ключа, которым ты подключён, — единственное действие,
        // способное отрезать тебя от сервера навсегда.
        .alert(item: $model.pendingKeyRemoval) { key in
            Alert(
                title: Text("удалить ключ, которым ты подключён?"),
                message: Text(
                    "\(key.comment ?? key.algorithm)\n\(key.fingerprint)\n\n"
                        + "после этого войти на сервер можно будет только другим ключом"),
                primaryButton: .destructive(Text("удалить")) { model.confirmKeyRemoval(key) },
                secondaryButton: .cancel(Text("отмена"))
            )
        }
        .sheet(isPresented: $model.isAddingHost) { HostEditor(model: model) }
        // Вопрос от MCP: показываем ровно то, что собираются сделать, и на
        // каком хосте. Согласиться вслепую здесь нельзя.
        .alert(item: $model.mcpConfirmation) { request in
            Alert(
                title: Text("ии просит выполнить на «\(request.host)»"),
                message: Text(request.what),
                primaryButton: .destructive(Text("разрешить")) {
                    request.answer(true)
                    model.mcpConfirmation = nil
                },
                secondaryButton: .cancel(Text("отклонить")) {
                    request.answer(false)
                    model.mcpConfirmation = nil
                }
            )
        }
        .task { await model.startBridge() }
        .onChange(of: model.page) { _, page in
            if page == .keys { Task { await model.loadKeys() } }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setWindowActive(phase == .active) }
        }
    }

    private var main: some View {
        CRTFrame {
            VStack(alignment: .leading, spacing: 0) {
                header
                Rule().padding(.top, 6).padding(.bottom, 14)
                content
                Rule().padding(.top, 12).padding(.bottom, 8)
                footer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text("PHOSPHOR")
                .font(model.style.font(11)).tracking(3)
                .foregroundStyle(model.style.muted)
            ForEach(tabs, id: \.0) { tab in
                Button {
                    model.screen = tab.1
                } label: {
                    HStack(spacing: 5) {
                        Text(model.screen == tab.1 ? "▸" : " ")
                        Text(model.strings(tab.0).uppercased())
                    }
                    .font(model.style.font(11)).tracking(1.2)
                    .foregroundStyle(model.screen == tab.1 ? model.style.bright : model.style.muted)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(headerRight)
                .font(model.style.font(11)).tracking(1.2)
                .foregroundStyle(model.style.muted)
        }
    }

    private var tabs: [(String, Section)] {
        [
            ("nav.hosts", .hosts), ("tab.terminal", .terminal), ("tab.files", .files),
            ("tab.docker", .docker), ("tab.monitor", .monitor),
            ("tab.provision", .provision), ("tab.activity", .activity),
            ("tab.theme", .theme),
        ]
    }

    private var headerRight: String {
        guard let id = model.selectedHost,
            let host = model.book.hosts.first(where: { $0.id == id })
        else { return "TOUCH ID" }
        return "\(host.name.uppercased()) · \(model.book.reach(for: host).summary.uppercased()) · TOUCH ID"
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .hosts: HostsView(model: model)
        case .terminal: TerminalPane(model: model)
        case .files: FilesView(model: model)
        case .docker: DockerView(model: model)
        case .monitor: MonitorView(model: model)
        case .provision: ProvisionView(model: model)
        case .activity: ActivityView(model: model)
        case .theme: ThemeView(model: model)
        }
        Spacer(minLength: 0)
    }

    private var footer: some View {
        HStack(spacing: 22) {
            Text("\(model.book.hosts.count) хостов · \(model.book.groups.count) групп")
            Text(model.style.theme.name)
            Spacer()
            Text(model.pet == .cat ? "котёнок спит" : "поссум спит")
        }
        .font(model.style.font(11)).tracking(1.1)
        .foregroundStyle(model.style.muted)
    }
}
