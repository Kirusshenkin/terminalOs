public import HostsKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// The terminal pane with the pet corner.
public struct TerminalPane: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 0) {
            // Рейл спейсов виден всегда: это и есть «пульт» herdr. Пустой — с
            // подсказкой подключиться, а не спрятанный, иначе фичу не найти.
            SessionRail(model: model)
            Rectangle().fill(style.rule).frame(width: 1)
            terminal
        }
        // Без соединения терминал — это этот Мак. К серверу подключаемся по
        // клику, а не потому, что он был открыт в прошлый раз.
        .onAppear { model.focusLocalIfIdle() }
        // Ничего не попадает в буфер обмена и не открывается, пока человек не
        // увидел, что именно. Согласиться вслепую — как раз то, чем пользуется
        // атака через OSC 52.
        .alert(item: $model.guardPrompt) { prompt in
            Alert(
                title: Text(strings(prompt.titleKey)),
                message: Text(prompt.detail),
                primaryButton: .default(Text(strings("common.allow"))) { model.accept(prompt) },
                secondaryButton: .cancel(Text(strings("common.deny")))
            )
        }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let offer = model.rememberOffer {
                rememberBanner(offer)
            }
            // Про соединение с сервером — только когда на него и смотрим:
            // у панели этого Мака своё состояние, и «подключаюсь…» над ней
            // означало бы неправду.
            if let note = phaseNote, !model.localFocused {
                Text(note)
                    .font(style.font(12))
                    .foregroundStyle(isFailure ? style.warning : style.muted)
                    .padding(.bottom, 8)
            }
            if model.canSplit || !model.extraPanes.isEmpty { splitBar }
            panes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Одна панель или несколько живых рядом/друг над другом.
    @ViewBuilder private var panes: some View {
        let extras = model.extraPanes
        if extras.isEmpty {
            hostSurface(model.terminalDestination)
        } else {
            let layout =
                model.splitVertical
                ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
            GeometryReader { geometry in
                let total = model.splitVertical ? geometry.size.width : geometry.size.height
                layout {
                    hostSurface(model.terminalDestination)
                        .frame(
                            width: model.splitVertical ? total * model.splitRatio : nil,
                            height: model.splitVertical ? nil : total * model.splitRatio)
                    handle(total: total)
                    extraPanes(extras)
                }
                .coordinateSpace(.named(Self.splitSpace))
            }
        }
    }

    @ViewBuilder private func extraPanes(_ extras: [AppModel.Pane]) -> some View {
                ForEach(Array(extras.enumerated()), id: \.element.id) { index, pane in
                    if index > 0 { divider }
                    ZStack(alignment: .topTrailing) {
                        hostSurface(pane.destination)
                        // Новая панель сперва спрашивает, что запустить (§23).
                        if model.pendingLaunch.contains(pane.destination) {
                            AgentPicker(strings: strings, installed: model.installedHere) { choice in
                                model.launch(choice, in: pane.destination)
                            }
                        }
                        // Закрыть панель — сессия за ней остаётся на сервере.
                        Button {
                            model.closePane(pane.name)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(style.muted)
                                .padding(5)
                        }
                        .buttonStyle(PressFeedback())
                        .accessibilityLabel(strings("common.close"))
                        .help("\(strings("cmd.closePane")) ⌘W")
                    }
                }
    }

    /// Граница между главной панелью и остальными: тянется мышью, двойной
    /// щелчок возвращает пополам. Двигается сама граница, без анимации.
    private func handle(total: CGFloat) -> some View {
        divider
            .padding(model.splitVertical ? .horizontal : .vertical, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                let cursor: NSCursor = model.splitVertical ? .resizeLeftRight : .resizeUpDown
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.splitSpace))
                    .onChanged { drag in
                        guard total > 0 else { return }
                        let position = model.splitVertical ? drag.location.x : drag.location.y
                        model.splitRatio = AppModel.clampedRatio(position / total)
                    }
                    .onEnded { _ in model.saveLayout() }
            )
            .onTapGesture(count: 2) {
                model.splitRatio = 0.5
                model.saveLayout()
            }
            .accessibilityLabel(strings("nav.splitHandle"))
    }

    private static let splitSpace = "split"

    /// Волосяная линия между панелями — по той стороне, вдоль которой они идут.
    private var divider: some View {
        Rectangle().fill(style.rule)
            .frame(
                width: model.splitVertical ? 1 : nil,
                height: model.splitVertical ? nil : 1)
    }

    private func hostSurface(_ destination: TerminalHost.Destination) -> some View {
        TerminalHost(
            theme: style.theme, surfaces: model.surfaces, destination: destination
        ) { request in
            Task { @MainActor in model.guardPrompt = GuardPrompt(request: request) }
        }
    }

    /// Тонкая полоса управления сплитом над терминалом.
    private var splitBar: some View {
        HStack(spacing: 10) {
            Spacer()
            // Добавить панель можно, пока их меньше потолка: за каждой стоит
            // живой ssh, и «ещё одна» без края — это утечка на экране.
            if model.canSplit {
                Button {
                    model.splitTerminal()
                } label: {
                    Label2(model.strings("term.split"))
                }
                .buttonStyle(PressFeedback())
                .help("\(model.strings("cmd.splitSide")) ⌘D · \(model.strings("cmd.splitBelow")) ⇧⌘D")
            }
            if !model.extraPanes.isEmpty {
                Button {
                    model.flipSplit()
                } label: {
                    Image(
                        systemName: model.splitVertical
                            ? "rectangle.split.2x1" : "rectangle.split.1x2"
                    )
                    .font(.system(size: 11)).foregroundStyle(style.muted)
                }
                .buttonStyle(PressFeedback())
                .accessibilityLabel(strings("nav.flipSplit"))
                .help(strings("nav.flipSplit"))
                Button {
                    model.closeSplit()
                } label: {
                    Label2(model.strings("term.unsplit"))
                }
                .buttonStyle(PressFeedback())
                .help("\(model.strings("cmd.closePane")) ⌘W")
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 6)
    }

    /// Тонкая полоса «запомнить этот сервер?» после подключения на лету.
    /// Данные уже подставлены — человеку остаётся только согласиться.
    private func rememberBanner(_ host: ServerHost) -> some View {
        HStack(spacing: 10) {
            Text("\(strings("term.remember")) \(host.user)@\(host.address)?")
                .font(style.font(12)).foregroundStyle(style.bright)
            Spacer()
            PhButton(strings("term.remember"), kind: .primary) { model.acceptRememberOffer() }
            PhButton(strings("term.nope")) { model.rememberOffer = nil }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(style.surface)
        .padding(.bottom, 8)
    }

    /// Что сейчас с соединением — одной строкой, с причиной.
    private var phaseNote: String? {
        switch model.sessionState.phase {
        case .idle: nil
        case .connecting: strings("term.connecting")
        case .probing: strings("term.probing")
        case .ready:
            model.sessionState.profile.map {
                "\($0.osName) \($0.osVersion) · \(strings("term.uptime")) \(strings.duration(seconds: $0.uptimeSeconds))"
            }
        case .failed(let failure): strings.connectionFailure(failure)
        }
    }

    private var isFailure: Bool {
        if case .failed = model.sessionState.phase { return true }
        return false
    }

}
