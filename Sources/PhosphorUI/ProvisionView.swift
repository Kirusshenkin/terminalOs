public import PhosphorCore
public import ProvisionKit
public import SessionKit
public import SwiftUI

/// Настройка свежего сервера: шаги слева, живой вывод справа.
public struct ProvisionView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            if model.session == nil {
                // Рецепт применяется к серверу, а не к приложению: без хоста
                // это пустой список шагов, и честнее сказать это прямо.
                HostPicker(
                    model: model,
                    title: strings("tab.provision"),
                    note: "рецепт выполняется на сервере — выбери, на каком"
                )
                .frame(maxWidth: 320, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                steps
                Rectangle().fill(style.rule).frame(width: 1)
                output
            }
        }
        .sheet(isPresented: $model.showsPlannedCommands) { plannedSheet }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("рецепт · базовый").font(style.font(15)).foregroundStyle(style.bright)
                if let profile = model.profile {
                    Text("\(profile.osName) \(profile.osVersion)")
                        .font(style.font(12)).foregroundStyle(style.muted)
                }
            }
            Text(counter).font(style.font(11.5)).foregroundStyle(style.muted)
            Rule()

            ForEach(model.provisionSteps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(mark(step.status))
                        .foregroundStyle(colour(step.status))
                        .frame(width: 14, alignment: .leading)
                    Text(step.title)
                        .foregroundStyle(colour(step.status))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(note(step.status))
                        .font(style.font(11))
                        .foregroundStyle(style.muted)
                        .frame(width: 150, alignment: .trailing)
                }
                .font(style.font(12))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if model.isProvisioning {
                    PhButton("остановить после шага", kind: .danger) { model.stopProvisioning() }
                } else {
                    PhButton(strings("provision.run"), kind: .primary) {
                        Task { await model.startProvisioning() }
                    }
                }
                PhButton(strings("provision.show")) { model.showsPlannedCommands = true }
            }

            // Правило, которого нет в обычных скриптах: сначала доказать, что
            // ключ работает, и только потом закрывать пароли.
            Text(
                "шаг «закрыть вход по паролю» выполнится только после того, "
                    + "как отдельное соединение по ключу успешно откроется"
            )
            .font(style.font(11))
            .foregroundStyle(style.warning)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.surface)
            .overlay(Rectangle().stroke(style.warning.opacity(0.4), lineWidth: 1))
        }
        .frame(width: 400, alignment: .leading)
    }

    private var counter: String {
        let done = model.provisionSteps.filter(\.isFinished).count
        return "\(done) из \(model.provisionSteps.count) · идемпотентно, установленное пропускается"
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(model.isProvisioning ? "● живой лог" : "лог")
                    .font(style.font(11))
                    .foregroundStyle(model.isProvisioning ? style.bright : style.muted)
                Spacer()
                Text(model.profile?.isRoot == true ? "root" : "sudo")
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.provisionLog.elements.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(style.font(11.5))
                            .foregroundStyle(line.hasPrefix("$ ") ? style.bright : style.text.opacity(0.8))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Точный список команд до запуска: согласиться вслепую здесь нельзя.
    private var plannedSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("что уйдёт на сервер").font(style.font(15)).foregroundStyle(style.bright)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.plannedCommands, id: \.step) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Label2(entry.step)
                            ForEach(entry.commands, id: \.self) { command in
                                Text(command)
                                    .font(style.font(11.5))
                                    .foregroundStyle(style.text.opacity(0.85))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                PhButton("закрыть") { model.showsPlannedCommands = false }
            }
        }
        .padding(22)
        .frame(width: 760, height: 520)
        .background(style.background)
    }

    private func mark(_ status: StepProgress.Status) -> String {
        switch status {
        case .waiting: "·"
        case .running: "▸"
        case .done: "✓"
        case .skipped: "="
        case .failed: "✗"
        }
    }

    private func colour(_ status: StepProgress.Status) -> Color {
        switch status {
        case .waiting: style.muted
        case .running: style.bright
        case .done: style.text
        case .skipped: style.muted
        case .failed: style.warning
        }
    }

    private func note(_ status: StepProgress.Status) -> String {
        switch status {
        case .waiting: strings("provision.waiting")
        case .running: strings("provision.running")
        case .done: strings("provision.done")
        case .skipped(let reason): reason
        case .failed(let reason): reason
        }
    }
}
