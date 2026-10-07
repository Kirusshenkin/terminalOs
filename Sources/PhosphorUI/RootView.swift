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
    @State private var chipHovered = false

    public init() {}

    public var body: some View {
        content
            .environment(\.style, model.style)
            .frame(minWidth: 1_060, minHeight: 680)
            // Меню живёт вне окна; модель ему отдаётся только пока окно открыто
            // и разблокировано — за замком клавиши ничего делать не должны.
            .focusedSceneValue(\.appModel, model.isUnlocked ? model : nil)
            .modifier(WindowModals(model: model))
            .modifier(Alerts(model: model))
            .task { await model.startBridge() }
            // Релизы проверяются и до входа: обновление не требует профиля.
            .task { model.startUpdateChecks() }
            .alert(model.strings("upd.interruptTitle"), isPresented: $model.updateNeedsConfirm) {
                Button(model.strings("upd.interruptGo"), role: .destructive) {
                    Task { await model.installUpdate(confirmed: true) }
                }
                Button(model.strings("common.cancel"), role: .cancel) {}
            } message: {
                Text(
                    "\(model.updateWouldInterrupt.joined(separator: ", ")) · \(model.strings("upd.interruptBody"))"
                )
            }
            // Опрос замирает, когда на окно никто не смотрит: терминал открыт
            // весь день, и фоновому окну незачем будить процессор.
            .task(id: scenePhase) { await model.setWindowActive(scenePhase == .active) }
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
                // Команда видна целиком до запуска: скрытых действий нет.
                .alert(item: $model.pendingTmuxInstall) { install in
                    Alert(
                        title: Text(model.strings("tmux.confirmTitle")),
                        message: Text(
                            model.strings(install.needsPassword ? "tmux.confirmCopy" : "tmux.confirmRun")
                                + "\n\n" + install.command),
                        primaryButton: .default(
                            Text(model.strings(install.needsPassword ? "tmux.copy" : "tmux.run"))
                        ) {
                            Task { await model.confirmTmuxInstall(install) }
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
                        message: Text(
                            model.mcpQueue.count > 1
                                ? "\(request.what)\n\n\(model.strings("ai.queueMore")) \(model.mcpQueue.count - 1)"
                                : request.what),
                        primaryButton: .destructive(Text(model.strings("common.allow"))) {
                            model.answer(request.id, allow: true)
                        },
                        secondaryButton: .cancel(Text(model.strings("common.deny"))) {
                            model.answer(request.id, allow: false)
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
                // Сервер не подключился — причина над разделом сервера, а не
                // «not connected» в углу метрик: со сменённым ключом хоста или
                // упавшим прокси из этого не понять, что делать.
                if case .failed(let failure) = model.sessionState.phase, serverTabs.contains(model.screen) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.strings.connectionFailure(failure))
                                .font(model.style.font(11.5))
                                .foregroundStyle(model.style.warning)
                                .fixedSize(horizontal: false, vertical: true)
                            if failure.needsTrust { fingerprintLine }
                        }
                        Spacer(minLength: 8)
                        if failure.needsTrust, model.pendingHostKey != nil {
                            Button {
                                Task { await model.trustPendingHost() }
                            } label: {
                                Text(model.strings("host.trust"))
                                    .font(model.style.font(11))
                                    .foregroundStyle(model.style.background)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(model.style.accent)
                            }
                            .buttonStyle(PressFeedback())
                        } else {
                            Button {
                                model.reconnect()
                            } label: {
                                Text("\(model.strings("cmd.reconnect")) ⇧⌘R")
                                    .font(model.style.font(11))
                                    .foregroundStyle(model.style.bright)
                            }
                            .buttonStyle(PressFeedback())
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(model.style.surface)
                    .overlay(Rectangle().stroke(model.style.warning.opacity(0.4), lineWidth: 1))
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

    /// Шапка делится по тому, к чему относится раздел, а не по алфавиту:
    /// слева — список серверов, в рамке — выбранный сервер и всё, что с ним
    /// делается, справа — то, что общее для всех серверов. Рамка отвечает на
    /// вопрос «почему Docker пустой»: потому что сервер в ней не выбран.
    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("PHOSPHOR")
                .font(model.style.font(11)).tracking(3)
                .foregroundStyle(model.style.muted)
                .padding(.trailing, updateBadge == nil ? 22 : 10)
            if let badge = updateBadge {
                badge.padding(.trailing, 18)
            }
            tab(.hosts)
                .padding(.trailing, 18)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                hostChip
                ForEach(serverTabs, id: \.self) { tab($0) }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(Rectangle().stroke(model.style.rule, lineWidth: 1))
            Spacer(minLength: 18)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ForEach(globalTabs, id: \.self) { tab($0) }
            }
        }
    }

    /// Метка обновления рядом с названием: видна с любого экрана, а щелчок по
    /// ней и есть «обновить». Нет обновления — нет и метки.
    private var updateBadge: AnyView? {
        switch model.updateState {
        case .idle:
            return nil
        case .available(let manifest):
            return AnyView(
                Button {
                    Task { await model.installUpdate() }
                } label: {
                    Text("↑ \(model.strings("upd.available")) \(manifest.version)")
                        .font(model.style.font(11)).tracking(1)
                        .foregroundStyle(model.style.background)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(model.style.accent)
                }
                .buttonStyle(PressFeedback())
                .help(model.strings("upd.hint")))
        case .installing:
            return AnyView(
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(model.strings("upd.installing"))
                        .font(model.style.font(11)).foregroundStyle(model.style.bright)
                })
        case .failed(let message, let retry):
            let label = Text("↑ \(model.strings("upd.failedShort"))")
                .font(model.style.font(11)).foregroundStyle(model.style.warning)
            guard retry != nil else { return AnyView(label.help(message)) }
            return AnyView(
                Button {
                    Task { await model.installUpdate() }
                } label: {
                    label
                }
                .buttonStyle(PressFeedback())
                .help("\(message) · \(model.strings("upd.retry"))"))
        }
    }

    private var serverTabs: [Section] { [.terminal, .files, .docker, .monitor, .server] }
    private var globalTabs: [Section] { [.keys, .activity, .theme] }

    private func tab(_ section: Section) -> some View {
        Button {
            select(section)
        } label: {
            HStack(spacing: 5) {
                // Место под маркер занято всегда, поэтому строка не
                // дёргается, когда он приезжает.
                Text(" ")
                    .overlay(alignment: .leading) {
                        if model.screen == section {
                            Text("▸")
                                .matchedGeometryEffect(id: "screenMarker", in: marker)
                        }
                    }
                Text(model.strings(title(section)).uppercased())
                // Метка у «Терминала»: где-то в сессии агент упёрся в
                // вопрос. Видно из любого раздела — иначе про него
                // узнаёшь, только когда сам заглянешь.
                if section == .terminal, model.blockedSessions > 0 {
                    Text("●")
                        .font(model.style.font(7))
                        .foregroundStyle(model.style.warning)
                        .help(model.strings("term.blockedHint"))
                }
            }
            .font(model.style.font(11)).tracking(1.2)
            .foregroundStyle(colour(for: section))
        }
        .buttonStyle(PressFeedback())
        // Маркер «▸» и точка — украшение; имя вкладки — её название (#6).
        .accessibilityLabel(model.strings(title(section)))
        .accessibilityAddTraits(model.screen == section ? .isSelected : [])
        .onHover { inside in
            // Подсветка под курсором мгновенная: это отклик, а не
            // анимация, и ждать его нельзя.
            hovered = inside ? section : (hovered == section ? nil : hovered)
        }
        // ⌘1…⌘9 по порядку в шапке: рука на клавиатуре и остаётся
        // на клавиатуре. Разделов ровно девять — в этом и смысл закрытого
        // списка.
        .keyboardShortcut(
            KeyEquivalent(Character("\((Section.allCases.firstIndex(of: section) ?? 0) + 1)")),
            modifiers: .command
        )
    }

    private func title(_ section: Section) -> String {
        switch section {
        case .hosts: "nav.hosts"
        case .terminal: "tab.terminal"
        case .files: "tab.files"
        case .docker: "tab.docker"
        case .monitor: "tab.monitor"
        case .server: "tab.server"
        case .keys: "tab.keys"
        case .activity: "nav.aiAccess"
        case .theme: "tab.theme"
        }
    }

    /// Сервер, к которому относятся вкладки в рамке. Без сервера он зовёт
    /// себя выбрать — ярко, потому что это и есть следующий шаг.
    ///
    /// Кнопка, а не системный `Menu`: у того на macOS из подписи остаётся
    /// только первый элемент, и вместо имени сервера в шапке висела точка.
    /// Щелчок открывает быстрое подключение — там поиск, а хостов десятки.
    private var hostChip: some View {
        Button {
            model.isQuickConnectOpen = true
        } label: {
            HStack(spacing: 6) {
                Text(model.currentHost == nil ? "○" : "●")
                    .foregroundStyle(chipColour)
                Text(chipTitle)
                    .foregroundStyle(model.currentHost == nil ? model.style.bright : model.style.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("▾").foregroundStyle(model.style.muted)
            }
            .font(model.style.font(11)).tracking(1.2)
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(chipHovered ? model.style.text.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedback())
        .onHover { chipHovered = $0 }
        .help(chipHelp)
        .accessibilityLabel(chipHelp)
    }

    /// Отпечаток незнакомого сервера — то, с чем человек сверяется, прежде
    /// чем нажать «доверять». Пока его нет, честно говорим, что ждём.
    @ViewBuilder private var fingerprintLine: some View {
        if let key = model.pendingHostKey {
            ForEach(key.fingerprints, id: \.self) { fingerprint in
                Text(fingerprint)
                    .font(model.style.font(11.5))
                    .foregroundStyle(model.style.bright)
                    .textSelection(.enabled)
            }
        } else if model.hostKeyScanFailed {
            Text(model.strings("err.scanFailed"))
                .font(model.style.font(11)).foregroundStyle(model.style.muted)
        } else {
            Text(model.strings("host.scanning"))
                .font(model.style.font(11)).foregroundStyle(model.style.muted)
        }
    }

    private var chipTitle: String {
        guard let host = model.currentHost else { return model.strings("head.pickServer").uppercased() }
        return host.name.uppercased()
    }

    /// Точка говорит, живо ли соединение, — тем же цветом, что и везде.
    private var chipColour: Color {
        guard model.currentHost != nil else { return model.style.muted }
        switch model.sessionState.phase {
        case .ready: return model.style.accent
        case .failed: return model.style.warning
        case .idle, .connecting, .probing: return model.style.muted
        }
    }

    private var chipHelp: String {
        guard let host = model.currentHost else { return model.strings("head.pickServerHint") }
        return "\(host.user)@\(host.address) · \(model.reachLabel(for: host))"
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

    /// Содержимое выбранного раздела.
    @ViewBuilder private var screenBody: some View {
        switch model.screen {
        case .hosts: HostsView(model: model)
        case .terminal: TerminalPane(model: model)
        case .files: FilesView(model: model)
        case .docker: DockerView(model: model)
        case .monitor: MonitorView(model: model)
        case .server: ServerView(model: model)
        case .keys: KeyringView(model: model)
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
                    ? model.strings.format("foot.petAsleep", model.petName(model.pet))
                    : ""
            )
        }
        .font(model.style.font(11)).tracking(1.1)
        .foregroundStyle(model.style.muted)
    }
}
