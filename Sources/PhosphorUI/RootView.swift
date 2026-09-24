public import SwiftUI

/// Окно: экран входа, пока не разблокировано, затем разделы.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// «Уменьшить движение» — не украшение, а конечный кадр сразу.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AppModel()
    /// Маркер раздела один на всю шапку: он переезжает, а не гаснет и
    /// зажигается в другом месте. Один главный объект — на нём и держится
    /// движение.
    @Namespace private var marker
    @State private var hovered: Section?

    public init() {}

    public var body: some View {
        content
            .environment(\.style, model.style)
            .frame(minWidth: 1_060, minHeight: 680)
            // Меню живёт вне окна; модель ему отдаётся только пока окно открыто
            // и разблокировано — за замком клавиши ничего делать не должны.
            .focusedSceneValue(\.appModel, model.isUnlocked ? model : nil)
            .modifier(Sheets(model: model))
            .modifier(Alerts(model: model))
            .task { await model.startBridge() }
            .onChange(of: model.page) { _, page in
                if page == .keys { Task { await model.loadKeys() } }
            }
            // Опрос замирает, когда на окно никто не смотрит: терминал открыт
            // весь день, и фоновому окну незачем будить процессор.
            .onChange(of: scenePhase) { _, phase in
                Task { await model.setWindowActive(phase == .active) }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isUnlocked {
            main
        } else {
            LockView(
                strings: model.strings,
                welcome: model.welcome,
                capability: model.strings.gateCapability(model.gateCapability),
                error: model.unlockError
            ) {
                await model.unlock()
                return model.isUnlocked
            }
        }
    }

    /// Формы поверх окна.
    private struct Sheets: ViewModifier {
        @Bindable var model: AppModel

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $model.isAddingHost) { HostEditor(model: model) }
                .sheet(isPresented: $model.isQuickConnectOpen) { QuickConnect(model: model) }
                .sheet(item: $model.editingHost) { host in
                    HostEditor(model: model, editing: host)
                }
                .sheet(isPresented: $model.isAddingGroup) {
                    GroupEditor(model: model)
                }
                .sheet(item: $model.editingGroup) { group in
                    GroupEditor(model: model, editing: group)
                }
        }
    }

    /// Вопросы, на которые обязан ответить человек.
    private struct Alerts: ViewModifier {
        @Bindable var model: AppModel

        func body(content: Content) -> some View {
            content
                // Замена чужого файла — не то, что делают мимоходом: путь виден
                // целиком, и согласие даётся на него, а не на «да».
                .alert(item: $model.pendingOverwrite) { request in
                    Alert(
                        title: Text(request.file.name),
                        message: Text(
                            "\(request.destination) — \(model.strings("files.exists"))"),
                        primaryButton: .destructive(Text(model.strings("files.replace"))) {
                            Task { await model.confirmOverwrite() }
                        },
                        secondaryButton: .cancel(Text(model.strings("common.cancel"))) {
                            model.cancelOverwrite()
                        }
                    )
                }
                .alert(item: $model.pendingHostRemoval) { host in
                    Alert(
                        title: Text("\(model.strings("common.delete")) «\(host.name)»?"),
                        message: Text(
                            "\(host.user)@\(host.address) — \(model.strings("alert.removeHost"))"),
                        primaryButton: .destructive(Text(model.strings("common.delete"))) {
                            model.removeHost(host.id)
                            model.pendingHostRemoval = nil
                        },
                        secondaryButton: .cancel(Text(model.strings("common.cancel")))
                    )
                }
                // Разрушающее действие называет контейнер по имени: «удалить»
                // без имени — это как раз то, о чём потом жалеют.
                .alert(item: $model.pendingResource) { pending in
                    Alert(
                        title: Text(
                            "\(model.strings.resourceTitle(pending.action)) "
                                + "«\(model.strings.resourceSubject(pending.action))»?"),
                        message: Text(model.strings.resourceWarning(pending.action)),
                        primaryButton: .destructive(Text(model.strings.resourceTitle(pending.action))) {
                            model.confirm(pending)
                        },
                        secondaryButton: .cancel(Text(model.strings("common.cancel")))
                    )
                }
                .alert(item: $model.pendingAction) { pending in
                    Alert(
                        title: Text(
                            "\(model.strings.containerAction(pending.action)) «\(pending.container.name)»?"),
                        message: Text(pending.container.image),
                        primaryButton: .destructive(Text(model.strings.containerAction(pending.action))) {
                            model.confirm(pending)
                        },
                        secondaryButton: .cancel(Text(model.strings("common.cancel")))
                    )
                }
                // Удаление ключа, которым ты подключён, — единственное действие,
                // способное отрезать от сервера навсегда.
                .alert(item: $model.pendingKeyRemoval) { key in
                    Alert(
                        title: Text(model.strings("alert.removeKeyTitle")),
                        message: Text(
                            "\(key.comment ?? key.algorithm)\n\(key.fingerprint)\n\n"
                                + model.strings("alert.removeKeyBody")),
                        primaryButton: .destructive(Text(model.strings("common.delete"))) {
                            model.confirmKeyRemoval(key)
                        },
                        secondaryButton: .cancel(Text(model.strings("common.cancel")))
                    )
                }
                // Вопрос от MCP: показываем ровно то, что собираются сделать.
                .alert(item: $model.mcpConfirmation) { request in
                    Alert(
                        title: Text("\(model.strings("alert.mcpAsks")) «\(request.host)»"),
                        message: Text(request.what),
                        primaryButton: .destructive(Text(model.strings("common.allow"))) {
                            request.answer(true)
                            model.mcpConfirmation = nil
                        },
                        secondaryButton: .cancel(Text(model.strings("common.deny"))) {
                            request.answer(false)
                            model.mcpConfirmation = nil
                        }
                    )
                }
        }
    }

    private var main: some View {
        ZStack(alignment: .topLeading) {
            crt
            // Своё меню поверх всего: системное покрасить нельзя, а фосфор
            // должен оставаться фосфором в том числе и здесь.
            if let host = model.menuHost {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.menuHost = nil }
                PhMenu(items: model.cardMenuItems(for: host)) { model.menuHost = nil }
                    .fixedSize()
                    .offset(x: model.menuPoint.x, y: model.menuPoint.y)
            }
        }
        .coordinateSpace(name: "root")
    }

    private var crt: some View {
        CRTFrame {
            VStack(alignment: .leading, spacing: 0) {
                header
                Rule().padding(.top, 6).padding(.bottom, 14)
                // Над любым разделом: несохранённый профиль касается всего
                // окна, и узнавать об этом на одной вкладке из восьми поздно.
                if let saveError = model.saveError {
                    Text(saveError)
                        .font(model.style.font(11.5))
                        .foregroundStyle(model.style.warning)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.style.surface)
                        .overlay(
                            Rectangle().stroke(model.style.warning.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.bottom, 12)
                }
                screenBody
                    .id(model.screen)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity
                        )
                    )
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
            ForEach(Array(tabs.enumerated()), id: \.element.0) { index, tab in
                Button {
                    select(tab.1)
                } label: {
                    HStack(spacing: 5) {
                        // Место под маркер занято всегда, поэтому строка не
                        // дёргается, когда он приезжает.
                        Text(" ")
                            .overlay(alignment: .leading) {
                                if model.screen == tab.1 {
                                    Text("▸")
                                        .matchedGeometryEffect(id: "screenMarker", in: marker)
                                }
                            }
                        Text(model.strings(tab.0).uppercased())
                        // Метка у «Терминала»: где-то в сессии агент упёрся в
                        // вопрос. Видно из любого раздела — иначе про него
                        // узнаёшь, только когда сам заглянешь.
                        if tab.1 == .terminal, model.blockedSessions > 0 {
                            Text("●")
                                .font(model.style.font(7))
                                .foregroundStyle(model.style.warning)
                                .help(model.strings("term.blockedHint"))
                        }
                    }
                    .font(model.style.font(11)).tracking(1.2)
                    .foregroundStyle(colour(for: tab.1))
                }
                .buttonStyle(PressFeedback())
                .onHover { inside in
                    // Подсветка под курсором мгновенная: это отклик, а не
                    // анимация, и ждать его нельзя.
                    hovered = inside ? tab.1 : (hovered == tab.1 ? nil : hovered)
                }
                // ⌘1…⌘8 по порядку разделов: рука на клавиатуре и остаётся
                // на клавиатуре. Больше девяти разделов не будет — в этом и
                // смысл закрытого списка.
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: .command
                )
            }
            Spacer()
            Menu {
                if model.book.hosts.isEmpty {
                    Text(model.strings("common.noHosts"))
                    Divider()
                    Button(model.strings("common.addHost")) {
                        model.screen = .hosts
                        model.isAddingHost = true
                    }
                } else {
                    ForEach(model.book.hosts) { host in
                        Button(action: { Task { await model.connect(to: host) } }) {
                            HStack {
                                if model.selectedHost == host.id {
                                    Image(systemName: "checkmark")
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.name)
                                    Text("\(host.user)@\(host.address)")
                                        .font(.system(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Divider()
                    Button(model.strings("common.addHost")) {
                        model.screen = .hosts
                        model.isAddingHost = true
                    }
                }
            } label: {
                Text(headerRight)
                    .font(model.style.font(11)).tracking(1.2)
                    .foregroundStyle(model.style.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
        }
    }

    /// Выбранный ярче всех, под курсором — на полпути, остальные приглушены.
    private func colour(for section: Section) -> Color {
        if model.screen == section { return model.style.bright }
        return hovered == section ? model.style.text : model.style.muted
    }

    /// Переключение раздела — одно движение: маркер переезжает, содержимое
    /// сменяется. Пружина короткая и почти без раскачки: это навигация, а не
    /// празднование.
    private func select(_ section: Section) {
        guard model.screen != section else { return }
        let scale = model.motion.scale
        guard !reduceMotion, scale > 0 else {
            model.screen = section
            return
        }
        withAnimation(.spring(response: 0.28 * scale, dampingFraction: 0.82)) {
            model.screen = section
        }
    }

    private var tabs: [(String, Section)] {
        [
            ("nav.hosts", .hosts), ("tab.terminal", .terminal), ("tab.files", .files),
            ("tab.docker", .docker), ("tab.monitor", .monitor),
            ("tab.provision", .provision), ("nav.aiAccess", .activity),
            ("tab.theme", .theme),
        ]
    }

    private var headerRight: String {
        guard let id = model.selectedHost,
            let host = model.book.hosts.first(where: { $0.id == id })
        else { return "TOUCH ID" }
        return "\(host.name.uppercased()) · \(model.strings.reach(model.book.reach(for: host)).uppercased()) · TOUCH ID"
    }

    /// Содержимое выбранного раздела.
    @ViewBuilder private var screenBody: some View {
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
            Text(
                "\(model.book.hosts.count) \(model.strings("foot.hosts")) · "
                    + "\(model.book.groups.count) \(model.strings("foot.groups"))"
            )
            Text(
                model.strings.themeName(
                    id: model.style.theme.id, fallback: model.style.theme.name)
            )
            Spacer()
            Text(
                model.petVisible
                    ? model.strings(model.pet == .cat ? "foot.catAsleep" : "foot.gliderAsleep")
                    : ""
            )
        }
        .font(model.style.font(11)).tracking(1.1)
        .foregroundStyle(model.style.muted)
    }
}
