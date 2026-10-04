public import AppKit
public import Foundation
public import PhosphorCore

/// Обновление из приложения (§20.1 плана): релиз — сигнал, кнопка в шапке —
/// действие.
@MainActor
extension AppModel {
    /// Что сейчас с обновлением — для кнопки в шапке.
    public enum UpdateState: Equatable {
        case idle
        case available(UpdateManifest)
        case installing(UpdateManifest)
        /// Повтор возможен, если манифест есть и сбой не в подписи.
        case failed(String, retry: UpdateManifest?)
    }

    /// Как часто спрашивать релизы. Чаще незачем: выпуски — раз в дни.
    static let updateCheckSeconds = 6.0 * 3600

    /// Сборка, которая сейчас запущена. nil — запуск не из бандла (`swift run`),
    /// и сравнивать не с чем.
    var runningBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    /// Начинает проверять релизы: сразу и затем раз в шесть часов.
    public func startUpdateChecks() {
        guard updateWatch == nil, let build = runningBuild else { return }
        updateWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkForUpdate(currentBuild: build)
                await AppModel.pause(seconds: Self.updateCheckSeconds)
            }
        }
    }

    func checkForUpdate(currentBuild: Int) async {
        // Пока ставится или уже предложено — не перебиваем.
        if case .installing = updateState { return }
        do {
            if let manifest = try await updater.check(currentBuild: currentBuild) {
                updateState = .available(manifest)
            }
        } catch .badSignature {
            // Подпись не сошлась — молчать нельзя: это либо поломка релиза,
            // либо подмена. Предлагать такое обновление тоже нельзя.
            updateState = .failed(strings("upd.badSignature"), retry: nil)
        } catch {
            // Нет сети — не повод тревожить: следующая проверка через шесть часов.
        }
    }

    /// Что оборвёт перезапуск: агенты в обычных шеллах этого Мака. Сессии
    /// tmux — здесь и на серверах — переживают его, а обычный шелл — нет.
    public var updateWouldInterrupt: [String] {
        // Даже ждущий ввода агент теряет разговор: процесс шелла умирает.
        guard let agent = plainShell?.agent else { return [] }
        return [agent.title]
    }

    /// Скачивает, проверяет, ставит и перезапускает приложение. Если
    /// перезапуск оборвёт работающего агента, сначала спрашивает.
    public func installUpdate(confirmed: Bool = false) async {
        if !confirmed, !updateWouldInterrupt.isEmpty {
            updateNeedsConfirm = true
            return
        }
        let manifest: UpdateManifest
        switch updateState {
        case .available(let offered), .failed(_, retry: let offered?): manifest = offered
        default: return
        }
        updateState = .installing(manifest)
        do {
            let app = try await updater.install(manifest, over: Bundle.main.bundleURL)
            try Updater.relaunch(app, after: ProcessInfo.processInfo.processIdentifier)
            NSApp?.terminate(nil)
        } catch let failure as Updater.Failure {
            updateState = .failed(message(for: failure), retry: failure == .badSignature ? nil : manifest)
        } catch {
            updateState = .failed("\(strings("upd.failed")) \(error.localizedDescription)", retry: manifest)
        }
    }

    private func message(for failure: Updater.Failure) -> String {
        switch failure {
        case .network: strings("upd.network")
        case .badSignature: strings("upd.badSignature")
        case .corrupted: strings("upd.corrupted")
        case .install(let detail): "\(strings("upd.failed")) \(detail)"
        }
    }
}
