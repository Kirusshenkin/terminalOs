public import SwiftUI
public import ThemeKit

/// Theme picker with a live preview.
public struct ThemeView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }
    private var current: Theme { BuiltInThemes.theme(id: model.themeID) }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(
                title: strings("tab.theme"), strings: strings, page: $model.themePage)
            Rectangle().fill(style.rule).frame(width: 1)
            themeList
            Rectangle().fill(style.rule).frame(width: 1)
            page
            preview.frame(width: 320)
        }
    }

    @ViewBuilder private var page: some View {
        switch model.themePage {
        case .palette:
            VStack(alignment: .leading, spacing: 14) {
                Label2("палитра ansi · \(current.name)")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8),
                    spacing: 5
                ) {
                    ForEach(Array(current.ansi.enumerated()), id: \.offset) { index, colour in
                        VStack(spacing: 3) {
                            Rectangle().fill(Color(colour)).frame(height: 26)
                            Text("\(index)").font(style.font(9)).foregroundStyle(style.muted)
                        }
                    }
                }
                Label2("особые цвета")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    swatch("текст", current.foreground)
                    swatch("фон", current.background)
                    swatch("курсор", current.cursor)
                    swatch("выделение", current.selection)
                }
                Label2("шрифт")
                HStack(spacing: 8) {
                    chip("IBM Plex Mono · 13")
                    chip("лигатуры")
                    chip("строка 1,4")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .glass:
            VStack(alignment: .leading, spacing: 10) {
                sliders
                Text(
                    "скан-линии и виньетка рисуются один раз и не стоят ничего "
                        + "на кадр: это не анимация, а статичный слой"
                )
                .font(style.font(11)).foregroundStyle(style.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .language:
            VStack(alignment: .leading, spacing: 14) {
                Label2(strings("settings.language"))
                ForEach(Language.allCases, id: \.self) { language in
                    Button {
                        model.language = language
                        model.saveAppearance()
                    } label: {
                        HStack(spacing: 6) {
                            Text(language == model.language ? "▸" : " ")
                            Text(language.title)
                        }
                        .font(style.font(12.5))
                        .foregroundStyle(language == model.language ? style.bright : style.text)
                    }
                    .buttonStyle(.plain)
                }
                Label2(strings("settings.eggs"))
                Toggle(
                    isOn: Binding(
                        get: { model.eggs.enabled },
                        set: {
                            model.eggs.enabled = $0; model.saveAppearance()
                        }
                    )
                ) {
                    Text("показывать отсылки").font(style.font(12)).foregroundStyle(style.text)
                }
                .toggleStyle(.switch)
                .tint(style.accent)
                Text(
                    "отсылка никогда не подменяет информацию: значок стоит рядом "
                        + "с настоящим числом, а не вместо него"
                )
                .font(style.font(11)).foregroundStyle(style.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func swatch(_ title: String, _ colour: RGBA) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(colour)).frame(width: 22, height: 16)
            Text(title).font(style.font(11.5)).foregroundStyle(style.muted)
            Spacer()
            Text(colour.hex).font(style.font(11)).foregroundStyle(style.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(style.surface)
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(style.font(11.5)).foregroundStyle(style.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(style.surface)
    }

    /// Список тем и куда они привязаны.
    private var themeList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(strings("settings.theme")).padding(.bottom, 6)
            ForEach(BuiltInThemes.all) { theme in
                Button {
                    model.themeID = theme.id
                    model.saveAppearance()
                } label: {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color(theme.ansi[10])).frame(width: 9, height: 9)
                        Text(theme.name)
                            .foregroundStyle(theme.id == model.themeID ? style.bright : style.text)
                        Spacer(minLength: 0)
                    }
                    .font(style.font(12.5))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(theme.id == model.themeID ? style.surface : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Label2("привязка").padding(.bottom, 4)
            ForEach(model.book.groups) { group in
                HStack(spacing: 6) {
                    Text(group.name).foregroundStyle(style.muted)
                    Spacer()
                    Text(group.themeID.map { BuiltInThemes.theme(id: $0).name } ?? "по умолчанию")
                        .foregroundStyle(style.text)
                }
                .font(style.font(11))
            }
        }
        .frame(width: 190, alignment: .leading)
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2("фон и стекло")
            row("скан-линии", current.scanlines)
            row("свечение", current.glow)
            row("виньетка", current.vignette)
            row("прозрачность окна", 1 - current.windowOpacity)
        }
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 10) {
            Text(title).font(style.font(11.5)).foregroundStyle(style.text).frame(
                width: 130, alignment: .leading)
            Bar(fraction: value, colour: style.accent)
            Text(percentLabel(value)).font(style.font(11)).foregroundStyle(style.muted).frame(
                width: 44, alignment: .trailing)
        }
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2("предпросмотр")
            VStack(alignment: .leading, spacing: 4) {
                line([("root@prod-01", 10), (":", 8), ("~", 12), ("# ls -la", 15)])
                line([("drwxr-xr-x", 12), ("  app  ", 15), ("config", 14), ("  deploy.sh", 11)])
                line([("● ", 10), ("api-gateway   Up 6 days", 15)])
                line([("○ ", 11), ("migrator      Exited (0)", 11)])
                line([("ERROR", 9), (" upstream billing unreachable", 15)])
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(current.background))
            .overlay(Rectangle().stroke(.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func line(_ parts: [(String, Int)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.0)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(current.ansi[part.1]))
            }
            Spacer(minLength: 0)
        }
    }
}
