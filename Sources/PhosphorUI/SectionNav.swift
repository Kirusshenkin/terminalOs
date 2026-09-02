public import SwiftUI

/// Раздел «Хосты» состоит из шести страниц.
public enum HostsPage: String, CaseIterable, Sendable {
    case hosts, keys, forwarding, snippets, known, log

    var key: String {
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

/// Навигация раздела. Кликается — в этом вся суть.
public struct SectionNav: View {
    @Environment(\.style) private var style
    private let strings: Strings
    @Binding private var page: HostsPage

    public init(strings: Strings, page: Binding<HostsPage>) {
        self.strings = strings
        self._page = page
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label2("— раздел —").padding(.bottom, 8)
            ForEach(HostsPage.allCases, id: \.self) { item in
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
        }
        .frame(width: 168, alignment: .leading)
    }
}
