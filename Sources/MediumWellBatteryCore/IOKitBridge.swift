import Foundation
import IOKit

/// Читает данные батареи из реестра IOKit.
///
/// Источники: узел `AppleSmartBattery` (состояние, адаптер, телеметрия
/// мощности) и узел `AppleSmartBatteryPack` (температура). Возвращает
/// `nil`, если батарея не обнаружена — например, на настольном Mac.
public final class IOKitBridge: Sendable {
    public init() {}

    /// Снимок данных батареи прямо сейчас.
    public func getBatteryInfo() -> BatteryInfo? {
        guard let batteryService = Self.findService("AppleSmartBattery") else {
            return nil
        }
        defer { IOObjectRelease(batteryService) }
        guard let battery = Self.properties(of: batteryService) else {
            return nil
        }

        let isPluggedIn = battery.bool("ExternalConnected")
        let isCharging = battery.bool("IsCharging")
        let cycleCount = battery.int("CycleCount") ?? 0

        // Заряд: на этой машине CurrentCapacity в процентах (MaxCapacity == 100),
        // но на части моделей значения в mAh — нормализуем к процентам.
        let currentCapacity = battery.int("CurrentCapacity") ?? 0
        let capacityScale = battery.int("MaxCapacity") ?? 100
        let currentCharge: Int
        if capacityScale > 0 && capacityScale <= 100 {
            currentCharge = currentCapacity
        } else if capacityScale > 100 {
            currentCharge = Int((Double(currentCapacity) / Double(capacityScale)) * 100.0)
        } else {
            currentCharge = 0
        }

        // Ёмкости (mAh) из BatteryData: проектная и текущая полная.
        let batteryData = battery.dict("BatteryData") ?? [:]
        let designCapacity = batteryData.int("DesignCapacity") ?? 0
        let maxCapacity = batteryData.int("FullChargeCapacity") ?? 0
        let nominalCapacity = batteryData.int("NominalChargeCapacity")

        // Электрика: Voltage в mV, InstantAmperage в mA.
        let voltage = (battery.double("Voltage") ?? 0) / 1000.0
        let amperage = (battery.double("InstantAmperage")
            ?? battery.double("Amperage") ?? 0) / 1000.0

        // Адаптер: AdapterDetails.Watts (nil, если адаптера нет).
        var adapterWatts: Double?
        if let adapter = battery.dict("AdapterDetails"),
           let watts = adapter.double("Watts"), watts > 0 {
            adapterWatts = watts
        }

        // Телеметрия мощности (mW → W): потребление системы и ток в батарею.
        var systemPowerWatts: Double?
        var batteryPowerWatts: Double?
        if let telemetry = battery.dict("PowerTelemetryData") {
            systemPowerWatts = telemetry.double("SystemLoad").map { $0 / 1000.0 }
            batteryPowerWatts = telemetry.double("BatteryPower").map { $0 / 1000.0 }
        }

        // Температура из AppleSmartBatteryPack: ключи Temperature / VirtualTemperature
        // лежат внутри словаря BatteryData узла pack.
        var temperature: Double?
        if let packService = Self.findService("AppleSmartBatteryPack") {
            defer { IOObjectRelease(packService) }
            if let pack = Self.properties(of: packService) {
                let packData = pack.dict("BatteryData") ?? [:]
                temperature = Self.normalizedTemperature(
                    packData.double("VirtualTemperature")
                        ?? packData.double("Temperature"))
            }
        }

        return BatteryInfo(
            currentCharge: currentCharge,
            maxCapacity: maxCapacity,
            designCapacity: designCapacity,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            voltage: voltage,
            amperage: amperage,
            temperature: temperature,
            cycleCount: cycleCount,
            adapterWatts: adapterWatts,
            systemPowerWatts: systemPowerWatts,
            batteryPowerWatts: batteryPowerWatts,
            nominalCapacity: nominalCapacity
        )
    }

    // MARK: - Нормализация данных

    /// Сырое значение температуры узла pack (сотые доли °C) → °C.
    /// Значения вне диапазона -10...100°C отбрасываются как невалидные.
    public static func normalizedTemperature(_ raw: Double?) -> Double? {
        guard let raw, (-10.0...100.0).contains(raw / 100.0) else {
            return nil
        }
        return raw / 100.0
    }

    // MARK: - IOKit

    private static func findService(_ className: String) -> io_service_t? {
        guard let matching = IOServiceMatching(className) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        return service
    }

    private static func properties(of service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}

// MARK: - Словарь свойств IOKit

private extension [String: Any] {
    func bool(_ key: String) -> Bool {
        self[key] as? Bool ?? false
    }

    func int(_ key: String) -> Int? {
        self[key] as? Int
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        return nil
    }

    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}
