public import Foundation
public import LocalAuthentication

/// Только что полученное подтверждение, что за клавиатурой владелец.
///
/// Вход спрашивает палец, а чтение ключа профиля сразу после — ещё раз (#5).
/// Доказательство передаётся от экрана входа к связке ключей: запись под
/// системным замком читается тем же контекстом, запись под замком приложения
/// не спрашивает повторно, пока подтверждение свежее.
///
/// `@unchecked Sendable`: `LAContext` не помечен как Sendable, но здесь он
/// после `evaluatePolicy` только читается — его отдают связке ключей по одному
/// запросу за раз, одновременно из двух мест его никто не трогает. Поле
/// неизменяемо, класс закрыт от наследования.
public final class OwnerProof: @unchecked Sendable {
    let context: LAContext
    private let confirmedAt: ContinuousClock.Instant

    public init(context: LAContext, confirmedAt: ContinuousClock.Instant = .now) {
        self.context = context
        self.confirmedAt = confirmedAt
    }

    /// Свежесть — верхняя граница, а не удобство: старое подтверждение не
    /// должно открывать то, о чём человек уже не помнит.
    func isFresh(within window: Duration, now: ContinuousClock.Instant = .now) -> Bool {
        now - confirmedAt <= window
    }
}
