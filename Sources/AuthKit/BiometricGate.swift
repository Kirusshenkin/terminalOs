public import Foundation
import LocalAuthentication

/// Why an unlock attempt did not succeed.
public enum GateError: Error, Equatable {
    /// The Mac cannot check anyone: no Touch ID, no watch, no password set.
    /// Carries the system's own explanation when it gave one.
    case unavailable(String?)
    /// The person cancelled, or failed too many times.
    case refused
    /// Biometry is present but locked out until a password is entered.
    case lockedOut
}

/// What this Mac can actually do, so the interface promises only that.
public struct GateCapability: Sendable, Equatable {
    public var hasBiometry: Bool
    public var hasWatch: Bool
    /// Always true when any policy can be evaluated: the account password is
    /// the floor beneath every other method.
    public var hasPassword: Bool

    public init(hasBiometry: Bool, hasWatch: Bool, hasPassword: Bool) {
        self.hasBiometry = hasBiometry
        self.hasWatch = hasWatch
        self.hasPassword = hasPassword
    }

}

/// Asks the system to confirm the person at the keyboard.
///
/// Touch ID is the fast path, never the only path. There is no Face ID on any
/// Mac, and there are Macs with no sensor at all, so the policy used is
/// `deviceOwnerAuthentication`: the system falls back to the watch or the
/// account password on its own. Locking someone out of their own profile is
/// not an acceptable outcome of a convenience feature.
public protocol BiometricGate: Sendable {
    /// Сколько одно подтверждение остаётся в силе. Короче окно — меньше шанс,
    /// что чужой процесс проскользнёт в него без нового прикосновения.
    var reuseDuration: TimeInterval { get set }
    func capability() -> GateCapability
    /// Спрашивает владельца; доказательство годится для чтения ключа сразу
    /// после, без второго прикосновения.
    @discardableResult
    func authenticate(reason: String) async throws -> OwnerProof
}

public struct SystemBiometricGate: BiometricGate {
    /// How long one confirmation stays valid.
    ///
    /// Without this a run of dangerous actions asks for a finger five times a
    /// minute and people start turning the feature off.
    public var reuseDuration: TimeInterval

    public init(reuseDuration: TimeInterval = 10) {
        self.reuseDuration = reuseDuration
    }

    public func capability() -> GateCapability {
        let context = LAContext()
        var error: NSError?
        let anyMethod = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        let biometry = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let watch = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithWatch, error: nil)
        return GateCapability(hasBiometry: biometry, hasWatch: watch, hasPassword: anyMethod)
    }

    @discardableResult
    public func authenticate(reason: String) async throws -> OwnerProof {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration
        // Кнопку «Отмена» система подписывает сама, на языке системы.

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw GateError.unavailable(error?.localizedDescription)
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return OwnerProof(context: context)
        } catch let failure as LAError where failure.code == .biometryLockout {
            throw GateError.lockedOut
        } catch {
            throw GateError.refused
        }
    }
}

// Замок, который всегда открыт, убран, а не удалён: им никто не пользовался,
// а в боевой сборке он лежал рядом с настоящим и отличался одной буквой в
// имени. Если понадобится для превью — место вот оно, но жить он должен в
// тестах, а не в отгружаемом коде.
//
// public struct OpenGate: BiometricGate {
//     public var reuseDuration: TimeInterval = 0
//     public init() {}
//     public func capability() -> GateCapability {
//         GateCapability(hasBiometry: true, hasWatch: false, hasPassword: true)
//     }
//     public func authenticate(reason: String) async throws {}
// }
