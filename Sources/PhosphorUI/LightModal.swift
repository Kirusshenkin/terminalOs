import SwiftUI

/// Окно поверх интерфейса вместо системного листа (#27).
///
/// Системный лист на macOS по клику мимо не закрывается вообще. Здесь клик
/// мимо закрывает — но только когда терять нечего. Форма с несохранённым
/// вводом сообщает об этом через `UnsavedInput`, и тогда клик мимо окно не
/// закрывает, а напоминает, что есть «сохранить» и «отмена». Esc и крестик
/// закрывают всегда: это явное «отмена», а не случайность.
struct LightModal<Panel: View>: ViewModifier {
    @Environment(\.style) private var style
    @Binding var isPresented: Bool
    let strings: Strings
    @ViewBuilder let panel: () -> Panel
    @State private var unsaved = false
    @State private var reminded = false

    func body(content: Content) -> some View {
        content
            // Под открытым окном интерфейс выключен целиком: иначе Tab уводил
            // бы фокус к кнопкам под затемнением, а VoiceOver читал бы всё окно.
            .disabled(isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.45)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: outsideClick)
                            .accessibilityHidden(true)
                        VStack(spacing: 8) {
                            panel()
                                .overlay(Rectangle().stroke(style.rule, lineWidth: 1))
                                .overlay(alignment: .topTrailing) { closeButton }
                                .onPreferenceChange(UnsavedInput.self) { value in
                                    unsaved = value
                                    if !value { reminded = false }
                                }
                            if reminded {
                                Text(strings("modal.unsaved"))
                                    .font(style.font(11.5)).foregroundStyle(style.warning)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(style.background)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .transition(.opacity)
                    .onDisappear {
                        unsaved = false
                        reminded = false
                    }
                }
            }
            .animation(.easeOut(duration: 0.12), value: isPresented)
            .animation(.easeOut(duration: 0.12), value: reminded)
    }

    private func outsideClick() {
        if unsaved {
            reminded = true
        } else {
            isPresented = false
        }
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Text("×").font(style.font(16)).foregroundStyle(style.muted)
                .padding(.horizontal, 10).padding(.vertical, 4)
        }
        .buttonStyle(PressFeedback())
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(strings("common.close"))
    }
}

/// Есть ли в окне ввод, который потеряется при закрытии.
struct UnsavedInput: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func lightModal(
        isPresented: Binding<Bool>, strings: Strings, @ViewBuilder panel: @escaping () -> some View
    ) -> some View {
        modifier(LightModal(isPresented: isPresented, strings: strings, panel: panel))
    }

    /// То же для окна, привязанного к значению: закрыть — значит обнулить его.
    func lightModal<Item>(
        item: Binding<Item?>, strings: Strings, @ViewBuilder panel: @escaping (Item) -> some View
    ) -> some View {
        let shown = Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        return modifier(
            LightModal(isPresented: shown, strings: strings) {
                if let value = item.wrappedValue { panel(value) }
            })
    }

    /// Отмечает окно как содержащее несохранённый ввод.
    func unsavedInput(_ value: Bool) -> some View { preference(key: UnsavedInput.self, value: value) }
}
