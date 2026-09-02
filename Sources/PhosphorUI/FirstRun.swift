public import HostsKit
public import KeysKit
public import SwiftUI

/// Что можно перенести в список, не спрашивая человека ни о чём.
///
/// Считается до нажатия, а не после: «в `~/.ssh/config` двенадцать серверов»
/// — это ответ, а «импортировать?» — вопрос. Первый экран должен отвечать.
public struct ImportOffer: Identifiable, Sendable {
    public var id: String { key }
    /// Ключ строки с названием источника.
    public let key: String
    /// Сколько серверов оттуда ещё не в списке.
    public let count: Int
    public let source: ImportSource
}

/// Откуда берём. Перечисление, а не замыкание: источник должен быть виден
/// в журнале и в тесте.
public enum ImportSource: String, Sendable, CaseIterable {
    case sshConfig, knownHosts, termius

    public var key: String {
        switch self {
        case .sshConfig: "hosts.import"
        case .knownHosts: "hosts.known"
        case .termius: "hosts.termius"
        }
    }
}

/// Первый экран, когда список пуст.
///
/// Пустой список — это не ошибка и не повод показать серую строчку. Это
/// единственный момент, когда человек ещё ничего не настроил, и приложение
/// может показать, что уже про него знает.
struct FirstRun: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    private var strings: Strings { model.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings("first.title"))
                .font(style.font(15))
                .foregroundStyle(style.bright)
            Text(strings("first.subtitle"))
                .font(style.font(12))
                .foregroundStyle(style.muted)
                .frame(maxWidth: 520, alignment: .leading)

            if model.importOffers.isEmpty {
                Text(strings("first.nothingFound"))
                    .font(style.font(12))
                    .foregroundStyle(style.muted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.importOffers) { offer in
                        offerRow(offer)
                    }
                }
            }

            HStack(spacing: 8) {
                PhButton(strings("hosts.new"), kind: .primary) { model.isAddingHost = true }
                PhButton(strings("first.localShell")) { model.screen = .terminal }
            }

            Text(strings("first.next"))
                .font(style.font(11.5))
                .foregroundStyle(style.muted)
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .task { model.refreshImportOffers() }
    }

    private func offerRow(_ offer: ImportOffer) -> some View {
        HStack(spacing: 10) {
            Text("\(offer.count)")
                .font(style.font(13))
                .foregroundStyle(style.bright)
                .frame(width: 34, alignment: .trailing)
            Text(strings(offer.key))
                .font(style.font(12.5))
                .foregroundStyle(style.text)
            Spacer(minLength: 12)
            PhButton(strings("first.take")) { model.take(offer) }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}
