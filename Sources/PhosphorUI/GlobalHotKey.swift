import AppKit
import Carbon.HIToolbox

/// ⌃` из любого приложения: показать Phosphor или убрать его обратно.
///
/// Через Carbon, а не через `NSEvent.addGlobalMonitorForEvents`: глобальный
/// монитор требует разрешения «Универсальный доступ» и видит все нажатия
/// в системе, а здесь регистрируется ровно одно сочетание — и только его
/// система нам и присылает. Выключено по умолчанию: чужое сочетание
/// без спроса не забирается.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isEnabled: Bool { hotKey != nil }

    /// Включает или выключает сочетание. Вернёт `false`, если система
    /// отказала — сочетание уже занято другим приложением.
    @discardableResult
    func set(enabled: Bool) -> Bool {
        if enabled == isEnabled { return true }
        return enabled ? register() : unregister()
    }

    private func register() -> Bool {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // Carbon зовёт обработчик на главном потоке, из цикла событий
            // приложения, — отсюда `assumeIsolated`.
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, _ in
                    MainActor.assumeIsolated { GlobalHotKey.toggleWindow() }
                    return noErr
                }, 1, &spec, nil, &handler)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: OSType(0x5048_4F53), id: 1)  // 'PHOS'
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Grave), UInt32(controlKey), id, GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    private func unregister() -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        return true
    }

    /// Окно впереди и в фокусе — убрать; иначе вытащить поверх всего.
    private static func toggleWindow() {
        if NSApp.isActive, NSApp.keyWindow != nil {
            NSApp.hide(nil)
            return
        }
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
