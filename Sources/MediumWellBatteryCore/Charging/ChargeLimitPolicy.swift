import Foundation

/// Режим управления зарядкой (FR-001..FR-003).
public enum ChargeMode: String, CaseIterable, Sendable {
    /// Обычный режим: заряд до установленного лимита.
    case limit
    /// Принудительный заряд до 100% без учёта лимита.
    case forceCharge
    /// Зарядка отключена до отмены пользователем.
    case forceDischarge
}

/// Решение «заряжать или удерживать» по текущему заряду, лимиту и режиму.
public enum ChargeLimitPolicy {
    /// Гистерезис: после остановки на лимите зарядка возобновляется,
    /// только когда заряд упал на столько процентов, — иначе на границе
    /// лимита зарядка включалась бы и выключалась на каждом проценте.
    public static let resumeMargin = 2

    public static func shouldAllowCharging(
        charge: Int,
        limit: Int,
        mode: ChargeMode,
        currentlyAllowed: Bool
    ) -> Bool {
        switch mode {
        case .forceCharge:
            return true
        case .forceDischarge:
            return false
        case .limit:
            // Лимит 100% — ограничение выключено.
            if limit >= 100 { return true }
            if charge >= limit { return false }
            if charge <= limit - resumeMargin { return true }
            return currentlyAllowed
        }
    }
}
