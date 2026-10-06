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
    public static let dischargeThreshold = 0.5

    public init(_ info: BatteryInfo) {
        let batteryPower = info.batteryPowerWatts ?? 0

        if let adapterInput = info.adapterInputWatts {
            // Есть датчик входа: источник — адаптер, пока он даёт питание.
            source = adapterInput > Self.dischargeThreshold ? .adapter : .battery
        } else {
            let discharging = batteryPower < -Self.dischargeThreshold
            source = info.isPluggedIn && !discharging ? .adapter : .battery
        }
        toBattery = source == .adapter ? max(batteryPower, 0) : 0

        if let system = info.systemPowerWatts, system > 0 {
            toSystem = system
        } else if source == .battery {
            // Телеметрии системы нет или она невалидна: всё, что отдаёт
            // батарея, потребляет система. Модуль — потому что в момент
            // отключения адаптера знак в телеметрии бывает перевёрнут.
            toSystem = batteryPower != 0
                ? abs(batteryPower) : abs(info.powerWatts)
        } else {
            toSystem = 0
        }
    }

    public var total: Double { toBattery + toSystem }

    /// Доля мощности, идущая в батарею, 0...1.
    public var batteryShare: Double {
        total > 0 ? toBattery / total : 0
    }
}
