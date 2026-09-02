public import SwiftUI

/// Страница внутри раздела.
///
/// Каждый раздел делится на страницы одинаково, поэтому и компонент один: два
/// разных списка слева, ведущие себя по-разному, — это то, из-за чего интерфейс
/// перестаёт быть предсказуемым.
public protocol SectionPage: Hashable, CaseIterable, Sendable {
    /// Ключ строки в таблице переводов.
    var key: String { get }
}

public enum HostsPage: String, SectionPage {
    case hosts, keys, forwarding, snippets, known, log

    public var key: String {
        switch self {
        case .hosts: "nav.hosts"
        case .keys: "nav.keys"
        case .forwarding: "nav.forwarding"
        case .snippets: "nav.snippets"
        case .known: "nav.known"
        case .log: "nav.log"
        }
    }
}

public enum DockerPage: String, SectionPage {
    case containers, images, volumes, networks

    public var key: String {
        switch self {
        case .containers: "nav.containers"
        case .images: "nav.images"
        case .volumes: "nav.volumes"
        case .networks: "nav.networks"
        }
    }
}

public enum MonitorPage: String, SectionPage {
    case overview, processes, storage, network

    public var key: String {
        switch self {
        case .overview: "nav.overview"
        case .processes: "nav.processes"
        case .storage: "nav.storage"
        case .network: "nav.netStat"
        }
    }
}

public enum ActivityPage: String, SectionPage {
    case journal, access, tools

    public var key: String {
        switch self {
        case .journal: "nav.journal"
        case .access: "nav.access"
        case .tools: "nav.tools"
        }
    }
}

public enum ThemePage: String, SectionPage {
    case palette, glass, language, behaviour

    public var key: String {
        switch self {
        case .palette: "nav.palette"
        case .glass: "nav.glass"
        case .language: "nav.language"
        case .behaviour: "nav.behaviour"
        }
    }
}

/// Навигация раздела. Кликается — в этом вся суть.
public struct SectionNav<Page: SectionPage>: View {
    @Environment(\.style) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    private let strings: Strings
    @Binding private var page: Page
    /// Тот же приём, что в шапке: маркер один и переезжает между строками.
    @Namespace private var marker
    @State private var hovered: Page?

    public init(title: String, strings: Strings, page: Binding<Page>) {
        self.title = title
        self.strings = strings
        self._page = page
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label2("— \(title) —").padding(.bottom, 8)
            ForEach(Array(Page.allCases), id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    HStack(spacing: 6) {
                        Text(" ")
                            .overlay(alignment: .leading) {
                                if page == item {
                                    Text("▸").matchedGeometryEffect(id: "pageMarker", in: marker)
                                }
                            }
                        Text(strings(item.key))
                        Spacer(minLength: 0)
                    }
                    .font(style.font(12.5))
                    .foregroundStyle(
                        page == item
                            ? style.bright
                            : (hovered == item ? style.bright.opacity(0.75) : style.text)
                    )
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedback())
                .onHover { inside in
                    hovered = inside ? item : (hovered == item ? nil : hovered)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 168, alignment: .leading)
    }

    private func select(_ item: Page) {
        guard page != item else { return }
        guard !reduceMotion else {
            page = item
            return
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { page = item }
    }
}

/// Нажатие: короткое сжатие и быстрый возврат. Только `scale` и `opacity`.
public struct PressFeedback: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1, anchor: .leading)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.10)
                    : .spring(response: 0.24, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}
