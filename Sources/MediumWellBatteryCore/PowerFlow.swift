import Foundation

/// Куда идёт энергия прямо сейчас (FR-005): от источника — в батарею
/// и на питание системы.
public struct PowerFlow: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Питание от адаптера.
        case adapter
        /// Питание от батареи: адаптера нет или он отключён лимитом.
        case battery
    }

    public let source: Source
    /// Мощность, идущая на зарядку батареи, Вт (0 — не заряжается).
    public let toBattery: Double
    /// Мощность, потребляемая системой, Вт.
    public let toSystem: Double

    /// Батарея отдаёт больше этого порога — источник она, а не адаптер.
    /// Порог отсекает шум измерений около нуля.
    static let dischargeThreshold = 0.5

    public init(_ info: BatteryInfo) {
        let batteryPower = info.batteryPowerWatts ?? 0
        let discharging = batteryPower < -Self.dischargeThreshold

        source = info.isPluggedIn && !discharging ? .adapter : .battery
        toBattery = source == .adapter ? max(batteryPower, 0) : 0

        if let system = info.systemPowerWatts, system > 0 {
            toSystem = system
        } else {
            // Телеметрии системы нет: при разрядке всё, что отдаёт
            // батарея, потребляет система.
            toSystem = max(-batteryPower, 0)
        }
    }

    public var total: Double { toBattery + toSystem }

    /// Доля мощности, идущая в батарею, 0...1.
    public var batteryShare: Double {
        total > 0 ? toBattery / total : 0
    }
}
