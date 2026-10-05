import Foundation

public struct BatteryInfo: Equatable, Sendable {
    public let currentCharge: Int
    public let maxCapacity: Int
    public let designCapacity: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let voltage: Double
    public let amperage: Double
    public let temperature: Double?
    public let cycleCount: Int
    /// Мощность подключённого адаптера (AdapterDetails.Watts), nil — адаптера нет.
    public let adapterWatts: Double?
    /// Потребление системы (PowerTelemetryData.SystemLoad, mW → W).
    public let systemPowerWatts: Double?
    /// Мощность, идущая в батарею (PowerTelemetryData.BatteryPower, mW → W).
    public let batteryPowerWatts: Double?

    public init(currentCharge: Int, maxCapacity: Int, designCapacity: Int,
                isCharging: Bool, isPluggedIn: Bool, voltage: Double,
                amperage: Double, temperature: Double?, cycleCount: Int,
                adapterWatts: Double? = nil, systemPowerWatts: Double? = nil,
                batteryPowerWatts: Double? = nil) {
        self.currentCharge = min(max(currentCharge, 0), 100)
        self.maxCapacity = max(maxCapacity, 0)
        self.designCapacity = max(designCapacity, 0)
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.voltage = max(voltage, 0)
        self.amperage = amperage
        self.temperature = temperature
        self.cycleCount = max(cycleCount, 0)
        self.adapterWatts = adapterWatts
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
    }

    public var healthPercentage: Int {
        guard designCapacity > 0 else { return 0 }
        // Ограничение выполняется до Int: иначе абсурдные значения
        // ломают преобразование.
        let ratio = Double(maxCapacity) / Double(designCapacity)
        return Int(min(max(ratio * 100.0, 0), 100))
    }

    public var powerWatts: Double {
        let magnitude = abs(voltage * amperage)
        // Знак по состоянию: зарядка — «плюс», разрядка — «минус» (FR-009).
        // Надёжнее знака InstantAmperage: на части моделей он приходит нулевым.
        if isCharging { return magnitude }
        if isPluggedIn && magnitude == 0 { return 0 }
        return -magnitude
    }

    public var condition: BatteryCondition {
        // Нет данных о проектной ёмкости — состояние неизвестно,
        // а не «требует обслуживания».
        guard designCapacity > 0 else { return .unknown }
        switch healthPercentage {
        case 80...: return .normal
        case 60..<80: return .replaceSoon
        default: return .serviceBattery
        }
    }
}

public enum BatteryCondition: String, Sendable {
    case normal = "Normal"
    case replaceSoon = "Replace Soon"
    case serviceBattery = "Service Battery"
    case unknown = "Unknown"
}

public enum TemperatureState: Equatable, Sendable {
    case normal
    case warning
    case critical

    public init(value: Double, warningThreshold: Double = 35, criticalThreshold: Double = 40) {
        if value > criticalThreshold {
            self = .critical
        } else if value >= warningThreshold {
            self = .warning
        } else {
            self = .normal
        }
    }
}

public struct ChargeSettings: Equatable, Sendable {
    public let limit: Int

    public init(limit: Int) {
        self.limit = min(max(limit, 20), 100)
    }
}
