public import DockerKit
public import HostsKit
public import KeysKit
public import PhosphorCore
public import SessionKit

/// Подписи для того, что приходит из пакетов.
///
/// Пакеты не знают языка интерфейса и не должны: они отдают тип или причину,
/// а слова подбираются здесь, по таблице. Иначе английский интерфейс
/// показывал бы «НАПРЯМУЮ» рядом с «HOSTS».
extension Strings {
    // MARK: Хосты

    public func reach(_ reach: Reach) -> String {
        switch reach {
        case .direct: self("reach.direct")
        case .socks(let host, let port): "\(self("reach.proxy")) \(host):\(port)"
        case .jump: self("reach.jump")
        }
    }

    public func guardLevel(_ level: GuardLevel) -> String {
        switch level {
        case .never: self("guard.never")
        case .dangerous: self("guard.dangerous")
        case .always: self("guard.always")
        }
    }

    public func mcpMode(_ mode: MCPMode) -> String {
        switch mode {
        case .disabled: self("mode.disabled")
        case .readOnly: self("mode.readOnly")
        case .confirm: self("mode.confirm")
        case .full: self("mode.full")
        }
    }

    public func connectionEvent(_ kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .connected: self("clog.connected")
        case .disconnected: self("clog.disconnected")
        case .failed: self("clog.failed")
        }
    }

    // MARK: Docker

    public func containerState(_ state: Container.State) -> String {
        switch state {
        case .running: self("cstate.running")
        case .exited: self("cstate.exited")
        case .paused: self("cstate.paused")
        case .restarting: self("cstate.restarting")
        case .created: self("cstate.created")
        case .dead: self("cstate.dead")
        case .unknown: self("cstate.unknown")
        }
    }

    public func containerAction(_ action: ContainerAction) -> String {
        self("caction.\(action.rawValue)")
    }

    public func resourceTitle(_ action: ResourceAction) -> String {
        switch action {
        case .removeImage: self("res.removeImage")
        case .pruneImages: self("res.pruneImages")
        case .removeVolume: self("res.removeVolume")
        case .pruneVolumes: self("res.pruneVolumes")
        case .removeNetwork: self("res.removeNetwork")
        case .pruneNetworks: self("res.pruneNetworks")
        }
    }

    /// Что именно уйдёт: имя объекта или описание всей чистки.
    public func resourceSubject(_ action: ResourceAction) -> String {
        switch action {
        case .removeImage(_, let name), .removeVolume(let name), .removeNetwork(_, let name): name
        case .pruneImages: self("res.pruneImagesSubject")
        case .pruneVolumes: self("res.pruneVolumesSubject")
        case .pruneNetworks: self("res.pruneNetworksSubject")
        }
    }

    public func resourceWarning(_ action: ResourceAction) -> String {
        switch action {
        case .removeImage: self("res.removeImageWarning")
        case .pruneImages: self("res.pruneImagesWarning")
        case .removeVolume: self("res.removeVolumeWarning")
        case .pruneVolumes: self("res.pruneVolumesWarning")
        case .removeNetwork: self("res.removeNetworkWarning")
        case .pruneNetworks: self("res.pruneNetworksWarning")
        }
    }

    public func imageName(_ image: DockerImage) -> String {
        image.isDangling ? self("res.untagged") : image.name
    }

    // MARK: Ключи, файлы, проброс

    public func keyWeakness(_ weakness: KeyWeakness) -> String {
        switch weakness {
        case .dsa: self("key.weakDSA")
        case .shortRSA(let bits): "RSA \(bits) \(self("key.weakRSA"))"
        }
    }

    public func knownHostName(_ entry: KnownHost) -> String {
        entry.host ?? self("known.hashed")
    }

    public func fileKind(_ kind: RemoteFile.Kind) -> String {
        switch kind {
        case .symlink: self("file.symlink")
        case .directory: self("file.directory")
        case .file(let ext): ext ?? self("file.plain")
        }
    }

    public func forwardDirection(_ direction: PortForward.Direction) -> String {
        switch direction {
        case .local: self("fwd.local")
        case .remote: self("fwd.remote")
        }
    }

    public func forwardSummary(_ forward: PortForward) -> String {
        let from = forward.direction == .local ? "localhost" : self("fwd.server")
        return "\(from):\(forward.listenPort) → \(forward.targetHost):\(forward.targetPort)"
    }

    // MARK: Числа

    /// Единицы на языке интерфейса. Считаются один раз на язык: размеры
    /// рисуются в мониторинге каждую секунду.
    private static let units: [Language: ByteFormat.Units] = Dictionary(
        uniqueKeysWithValues: Language.allCases.map { language in
            let strings = Strings(language: language)
            return (
                language,
                ByteFormat.Units(
                    sizes: ["unit.b", "unit.kb", "unit.mb", "unit.gb", "unit.tb", "unit.pb"].map { strings($0) },
                    day: strings("unit.day"), hour: strings("unit.hour"),
                    minute: strings("unit.minute"), second: strings("unit.second"))
            )
        })

    public func size(_ bytes: Int64) -> String {
        ByteFormat.size(bytes, units: Self.units[language] ?? .russian)
    }

    public func duration(seconds: Int) -> String {
        ByteFormat.duration(seconds: seconds, units: Self.units[language] ?? .russian)
    }
}
