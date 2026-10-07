import Foundation
import Testing

@testable import HostsKit
@testable import PhosphorCore
@testable import PhosphorUI
@testable import ProvisionKit

@Suite("Мак в роли сервера")
struct MacHostTests {
    /// Что печатает проба на macOS: ни /etc/os-release, ни /proc, ни apt.
    private let macOutput = """
        KERNEL Darwin
        OS macos 15.1
        UP 93026
        ID 501
        SUDO no
        DOCKER /usr/local/bin/docker
        PODMAN -
        DOCKEROK yes
        NGINX -
        CERTBOT -
        UFW -
        PKG brew
        CONTAINERS 2
        KEYS 1
        """

    @Test("мак узнаётся по ядру, а не по догадке")
    func detectsDarwin() {
        let profile = HostProbe.parse(macOutput)
        #expect(profile.osFamily == .darwin)
        #expect(profile.displayName == "macOS 15.1")
        #expect(!profile.hasProcMetrics, "метрики читаются из /proc, на маке его нет")
        #expect(!profile.isProvisionable)
    }

    @Test("профиль из кэша без поля ядра читается как Linux")
    func oldProfileIsLinux() throws {
        let old = #"""
            {"osName":"ubuntu","osVersion":"24.04","uptimeSeconds":1,"isRoot":true,"canSudo":true,
            "dockerNeedsSudo":false,"isPodman":false,"hasNginx":false,"hasCertbot":false,"hasUFW":false,
            "containerCount":0,"authorizedKeyCount":1,"packageManager":"apt"}
            """#
        let profile = try JSONDecoder().decode(HostProfile.self, from: Data(old.utf8))
        #expect(profile.kernelName == nil)
        #expect(profile.osFamily == .linux)
        #expect(profile.hasProcMetrics)
    }

    @Test("на маке не закрываем пароли: команды шага — для Linux")
    func passwordsNeedLinux() {
        let plan = BuiltInRecipe.base(RecipeInputs()).plan(for: HostProbe.parse(macOutput))
        #expect(plan.last?.step.id == "passwords")
        #expect(plan.last?.skip == .needsLinux)
        #expect(plan.allSatisfy { $0.skip?.isUnsupported == true }, "на маке не запускается ни один шаг")
    }

    @Test("команда установки — под пакетный менеджер сервера")
    func installCommand() {
        var profile = HostProbe.parse(macOutput)
        #expect(profile.installCommand(for: "tmux") == "brew install tmux")
        profile.packageManager = "apt"
        #expect(profile.installCommand(for: "tmux") == "sudo apt install -y tmux")
        profile.isRoot = true
        profile.packageManager = "dnf"
        #expect(profile.installCommand(for: "tmux") == "dnf install -y tmux")
        profile.packageManager = nil
        #expect(profile.installCommand(for: "tmux") == nil, "угаданная команда хуже никакой")
    }

    @Test("подсказка про tmux не советует apt маку")
    func tmuxHint() {
        let strings = Strings(language: .english)
        #expect(strings.noTmux(HostProbe.parse(macOutput)).hasSuffix("brew install tmux"))
        #expect(!strings.noTmux(nil).contains("apt"))
    }

    @Test("на карточке мака — MAC")
    func badge() {
        let host = ServerHost(name: "mini", address: "192.0.2.5", osName: "macos")
        #expect(host.osBadge == "MAC")
    }

    @Test("удалённые команды видят Homebrew")
    func homebrewOnPath() {
        #expect(HostProbe.command.hasPrefix(Shell.withPackagePaths))
        #expect(Shell.withPackagePaths.contains("/opt/homebrew/bin"))
    }
}
