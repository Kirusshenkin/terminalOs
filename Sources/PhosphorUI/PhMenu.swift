public import AppKit
public import SwiftUI

/// Пункт своего меню.
public struct MenuItem: Identifiable {
    public enum Kind { case normal, destructive, separator }

    public var id = UUID()
    public var title: String
    public var kind: Kind
    public var action: () -> Void

    public init(_ title: String, kind: Kind = .normal, action: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    public static var separator: MenuItem { MenuItem("", kind: .separator) }
}

/// Контекстное меню в стиле приложения.
///
/// Системное `NSMenu` покрасить нельзя: оно приходит со своим шрифтом,
/// скруглениями и синей подсветкой — и рвёт фосфор ровно там, где на него и
/// смотрят. Поэтому меню своё: те же прямые углы, тот же моноширинный шрифт,
/// та же подсветка, что у остального интерфейса.
public struct PhMenu: View {
    @Environment(\.style) private var style
    @State private var hovered: UUID?

    private let items: [MenuItem]
    private let dismiss: () -> Void

    public init(items: [MenuItem], dismiss: @escaping () -> Void) {
        self.items = items
        self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                if item.kind == .separator {
                    Rectangle().fill(style.rule).frame(height: 1)
                        .padding(.vertical, 4)
                } else {
                    row(item)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 176, alignment: .leading)
        .background(style.background)
        .overlay(Rectangle().stroke(style.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
    }

    private func row(_ item: MenuItem) -> some View {
        let isHovered = hovered == item.id
        return Text(item.title)
            .font(style.font(12.5))
            .foregroundStyle(colour(item, hovered: isHovered))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? style.accent.opacity(0.16) : .clear)
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? item.id : nil }
            .onTapGesture {
                dismiss()
                item.action()
            }
    }

    private func colour(_ item: MenuItem, hovered: Bool) -> Color {
        switch item.kind {
        case .destructive: hovered ? style.danger : style.warning
        case .normal: hovered ? style.bright : style.text
        case .separator: style.rule
        }
    }
}

/// Ловит правый клик и сообщает, где он случился.
///
/// Прозрачный слой поверх содержимого: левый клик проходит насквозь, правый
/// перехватывается, а системное меню подавляется — иначе оно всплыло бы поверх
/// нашего.
public struct RightClickCatcher: NSViewRepresentable {
    private let onClick: (CGPoint) -> Void

    public init(onClick: @escaping (CGPoint) -> Void) {
        self.onClick = onClick
    }

    public func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {
        (view as? CatcherView)?.onClick = onClick
    }

    final class CatcherView: NSView {
        var onClick: ((CGPoint) -> Void)?

        /// Левый клик и всё остальное идут мимо: слой существует только ради
        /// правой кнопки.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func rightMouseDown(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            onClick?(CGPoint(x: local.x, y: bounds.height - local.y))
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

public extension View {
    /// Своё контекстное меню вместо системного.
    func phContextMenu(
        isPresented: Binding<Bool>,
        point: Binding<CGPoint>,
        items: @escaping () -> [MenuItem]
    ) -> some View {
        overlay {
            GeometryReader { geometry in
                RightClickCatcher { local in
                    let origin = geometry.frame(in: .named("root")).origin
                    point.wrappedValue = CGPoint(x: origin.x + local.x, y: origin.y + local.y)
                    isPresented.wrappedValue = true
                }
            }
        }
    }
}
