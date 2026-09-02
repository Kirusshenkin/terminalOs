public import Foundation
import LocalAuthentication

/// Why an unlock attempt did not succeed.
public enum GateError: Error, Equatable {
    /// The Mac cannot check anyone: no Touch ID, no watch, no password set.
    case unavailable(String)
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

    /// A short line for the lock screen listing the ways in that exist here.
    public var summary: String {
        var parts: [String] = []
        if hasBiometry { parts.append("Touch ID") }
        if hasWatch { parts.append("Apple Watch") }
        if hasPassword { parts.append("пароль") }
        return parts.joined(separator: " · ")
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
    func authenticate(reason: String) async throws
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

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration
        context.localizedCancelTitle = "Отмена"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw GateError.unavailable(error?.localizedDescription ?? "проверка недоступна")
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let failure as LAError where failure.code == .biometryLockout {
            throw GateError.lockedOut
        } catch {
            throw GateError.refused
        }
    }
}

/// A gate that always succeeds. For tests and previews only.
public struct OpenGate: BiometricGate {
    public var reuseDuration: TimeInterval = 0
    public init() {}
    public func capability() -> GateCapability {
        GateCapability(hasBiometry: true, hasWatch: false, hasPassword: true)
    }
    public func authenticate(reason: String) async throws {}
}
