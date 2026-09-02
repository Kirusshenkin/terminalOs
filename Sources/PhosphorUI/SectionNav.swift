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
    private let title: String
    private let strings: Strings
    @Binding private var page: Page

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
                    page = item
                } label: {
                    HStack(spacing: 6) {
                        Text(page == item ? "▸" : " ")
                        Text(strings(item.key))
                        Spacer(minLength: 0)
                    }
                    .font(style.font(12.5))
                    .foregroundStyle(page == item ? style.bright : style.text)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 168, alignment: .leading)
    }
}
