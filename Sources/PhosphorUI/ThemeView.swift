public import SwiftUI
public import ThemeKit

/// Theme picker with a live preview.
public struct ThemeView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }
    private var current: Theme { model.theme(id: model.themeID) }

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
                HStack {
                    Label2(
                        "\(strings("set.palette")) · \(strings.themeName(id: current.id, fallback: current.name))"
                    )
                    Spacer()
                    PhButton(strings("set.import")) { model.importTheme() }
                }
                if let note = model.themeImportNote {
                    Text(note).font(style.font(11)).foregroundStyle(style.muted)
                }
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
                Label2(strings("set.special"))
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    swatch(strings("set.text"), current.foreground)
                    swatch(strings("set.bg"), current.background)
                    swatch(strings("set.cursor"), current.cursor)
                    swatch(strings("set.selection"), current.selection)
                }
                Label2(strings("set.font"))
                HStack(spacing: 8) {
                    stepper(
                        strings("set.size"), value: model.fontSize, unit: strings("set.pt"), step: 1,
                        range: 10...20
                    ) {
                        model.fontSize = $0
                        model.saveAppearance()
                    }
                    toggleChip(strings("set.ligatures"), on: model.ligatures) {
                        model.ligatures.toggle()
                        model.saveAppearance()
                    }
                    stepper(
                        strings("set.lineHeight"), value: model.lineHeight, unit: "", step: 0.1,
                        range: 1.0...2.0
                    ) {
                        model.lineHeight = $0
                        model.saveAppearance()
                    }
                }
                Text(strings("set.fontNote"))
                    .font(style.font(10.5)).foregroundStyle(style.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .glass:
            VStack(alignment: .leading, spacing: 10) {
                sliders
                Text(strings("set.glassNote"))
                    .font(style.font(11)).foregroundStyle(style.muted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .behaviour:
            VStack(alignment: .leading, spacing: 14) {
                Label2(strings("set.pet"))
                HStack(spacing: 8) {
                    ForEach(Pet.allCases, id: \.self) { pet in
                        toggleChip(pet.title.lowercased(), on: model.petVisible && model.pet == pet) {
                            model.pet = pet
                            model.petVisible = true
                            model.saveAppearance()
                        }
                    }
                    toggleChip(strings("set.off"), on: !model.petVisible) {
                        model.petVisible.toggle()
                        model.saveAppearance()
                    }
                }
                Text(strings("set.petNote"))
                    .font(style.font(11)).foregroundStyle(style.muted)

                Label2(strings("set.motion"))
                HStack(spacing: 8) {
                    ForEach(MotionAmount.allCases, id: \.self) { amount in
                        toggleChip(strings(amount.key), on: model.motion == amount) {
                            model.motion = amount
                            model.saveAppearance()
                        }
                    }
                }
                Label2(strings("set.connectMotion"))
                HStack(spacing: 8) {
                    ForEach(ConnectMotion.allCases, id: \.self) { kind in
                        toggleChip(strings(kind.key), on: model.connectMotion == kind) {
                            model.connectMotion = kind
                            model.saveAppearance()
                        }
                    }
                }
                Label2(strings("set.logMotion"))
                HStack(spacing: 8) {
                    ForEach(LogMotion.allCases, id: \.self) { kind in
                        toggleChip(strings(kind.key), on: model.logMotion == kind) {
                            model.logMotion = kind
                            model.saveAppearance()
                        }
                    }
                }
                Text(strings("set.motionNote"))
                    .font(style.font(11)).foregroundStyle(style.muted)

                Label2(strings("set.poll"))
                HStack(spacing: 8) {
                    stepper(
                        strings("set.interval"), value: model.pollSeconds, unit: strings("set.sec"), step: 1,
                        range: 1...30
                    ) {
                        model.pollSeconds = $0
                        model.saveAppearance()
                        model.applyPollInterval()
                    }
                }
                Text(strings("set.pollNote"))
                    .font(style.font(11)).foregroundStyle(style.muted)

                Label2(strings("set.logBuffer"))
                HStack(spacing: 8) {
                    ForEach([500, 2_000, 5_000, 20_000], id: \.self) { lines in
                        toggleChip("\(lines)", on: model.logLines == lines) {
                            model.logLines = lines
                            model.saveAppearance()
                            model.applyLogCapacity()
                        }
                    }
                }
                Text(strings("set.logNote"))
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
                    Text(strings("set.showEggs")).font(style.font(12)).foregroundStyle(style.text)
                }
                .toggleStyle(.switch)
                .tint(style.accent)
                Text(strings("set.eggsNote"))
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

    /// Значение с двумя кнопками: цифра, которую можно менять, а не подпись.
    private func stepper(
        _ title: String, value: Double, unit: String, step: Double,
        range: ClosedRange<Double>, set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title).font(style.font(11.5)).foregroundStyle(style.muted)
            Button {
                set(max(range.lowerBound, value - step))
            } label: {
                Text("−").font(style.font(13)).foregroundStyle(style.text).frame(width: 16)
            }
            .buttonStyle(.plain)
            Text(step < 1 ? String(format: "%.1f", value) : String(Int(value)) + unit)
                .font(style.font(11.5)).foregroundStyle(style.bright)
                .frame(width: 38)
            Button {
                set(min(range.upperBound, value + step))
            } label: {
                Text("+").font(style.font(13)).foregroundStyle(style.text).frame(width: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(style.surface)
    }

    private func toggleChip(
        _ title: String, on: Bool, toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(on ? "●" : "○").foregroundStyle(on ? style.accent : style.muted)
                Text(title).foregroundStyle(on ? style.text : style.muted)
            }
            .font(style.font(11.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(style.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Список тем и куда они привязаны.
    private var themeList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(strings("settings.theme")).padding(.bottom, 6)
            ForEach(model.allThemes) { theme in
                Button {
                    model.themeID = theme.id
                    model.saveAppearance()
                } label: {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color(theme.ansi[10])).frame(width: 9, height: 9)
                        Text(strings.themeName(id: theme.id, fallback: theme.name))
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
            Label2(strings("set.binding")).padding(.bottom, 4)
            ForEach(model.book.groups) { group in
                // Клик привязывает выбранную тему к группе: прод красный не
                // ради красоты, а чтобы окно нельзя было перепутать.
                Button {
                    model.bindTheme(model.themeID, to: group)
                } label: {
                    HStack(spacing: 6) {
                        Text(group.name).foregroundStyle(style.muted)
                        Spacer()
                        Text(
                            group.themeID.map {
                                strings.themeName(id: $0, fallback: BuiltInThemes.theme(id: $0).name)
                            }
                                ?? strings("set.default")
                        )
                        .foregroundStyle(style.text)
                    }
                    .font(style.font(11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(strings("set.bindingNote"))
                .font(style.font(10)).foregroundStyle(style.muted).padding(.top, 4)
        }
        .frame(width: 190, alignment: .leading)
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(strings("set.glass"))
            row(strings("set.scanlines"), current.scanlines) {
                model.scanlines = $0
                model.saveAppearance()
            }
            row(strings("set.glow"), current.glow) {
                model.glow = $0
                model.saveAppearance()
            }
            row(strings("set.vignette"), current.vignette) {
                model.vignette = $0
                model.saveAppearance()
            }
            PhButton(strings("set.resetGlass")) {
                model.scanlines = nil
                model.glow = nil
                model.vignette = nil
                model.saveAppearance()
            }
        }
    }

    /// Полоса, по которой можно кликать и тянуть: доля берётся из позиции
    /// курсора. Показывать значение и не давать его менять — обман.
    private func row(
        _ title: String, _ value: Double, set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title).font(style.font(11.5)).foregroundStyle(style.text)
                .frame(width: 150, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(style.text.opacity(0.12))
                    Rectangle().fill(style.accent)
                        .frame(width: geometry.size.width * min(max(value, 0), 1))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        set(min(max(drag.location.x / geometry.size.width, 0), 1))
                    }
                )
            }
            .frame(height: 7)
            Text(percentLabel(value)).font(style.font(11)).foregroundStyle(style.muted)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(strings("set.preview"))
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
