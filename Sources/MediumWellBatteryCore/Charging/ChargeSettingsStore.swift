import Foundation

/// Сохранение настроек зарядки между запусками (FR-001).
public struct ChargeSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    private enum Key {
        static let limit = "chargeLimit"
        static let lastAppliedAllowed = "chargeLastAppliedAllowed"
        static let keepHoldDuringSleep = "chargeKeepHoldDuringSleep"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Лимит заряда, 20...100%. По умолчанию 100 — ограничение выключено,
    /// пока пользователь сам его не задал.
    public var limit: Int {
        get {
            guard defaults.object(forKey: Key.limit) != nil else { return 100 }
            return ChargeSettings(limit: defaults.integer(forKey: Key.limit)).limit
        }
        nonmutating set {
            defaults.set(ChargeSettings(limit: newValue).limit, forKey: Key.limit)
        }
    }

    /// Последнее подтверждённое состояние: была ли зарядка разрешена.
    /// Нужно после перезапуска: удержание в SMC переживает выход из
    /// приложения, и его надо уметь снять.
    public var lastAppliedAllowed: Bool {
        get {
            guard defaults.object(forKey: Key.lastAppliedAllowed) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.lastAppliedAllowed)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.lastAppliedAllowed)
        }
    }

    /// Сохранять удержание заряда во сне. По умолчанию выключено:
    /// во сне приложение не работает и не может вернуть зарядку.
    public var keepHoldDuringSleep: Bool {
        get { defaults.bool(forKey: Key.keepHoldDuringSleep) }
        nonmutating set { defaults.set(newValue, forKey: Key.keepHoldDuringSleep) }
    }
}
