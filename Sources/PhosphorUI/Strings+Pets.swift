public import PetKit

extension Strings {
    public func petFileError(_ error: PetFileError) -> String {
        switch error {
        case .tooLarge: self("pf.tooLarge")
        case .notJSON(let detail): format("pf.notJSON", detail)
        case .unsupportedFormat(let version): format("pf.format", "\(version)")
        case .badID(let id): format("pf.badID", id)
        case .reservedID(let id): format("pf.reservedID", id)
        case .badName: self("pf.badName")
        case .missingState(let state): format("pf.missingState", state)
        case .unknownState(let state): format("pf.unknownState", state)
        case .frameCount(let state): format("pf.frameCount", state)
        case .frameSize(let place): format("pf.frameSize", place)
        case .ragged(let place): format("pf.ragged", place)
        case .unknownInk(let place, _): format("pf.unknownInk", place)
        case .badDuration(let state): format("pf.badDuration", state)
        case .exists(let id): format("pf.exists", id)
        case .notFound(let id): format("pf.notFound", id)
        case .cannotRead(let detail): format("pf.cannotRead", detail)
        case .cannotWrite(let detail): format("pf.cannotWrite", detail)
        }
    }
}
