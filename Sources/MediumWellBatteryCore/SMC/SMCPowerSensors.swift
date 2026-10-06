import Foundation

/// Мгновенные показания мощности, Вт.
public struct PowerReading: Equatable, Sendable {
    /// Мощность, приходящая от адаптера.
    public let adapterInput: Double
    /// Потребление системы.
    public let system: Double
    /// Мощность батареи: плюс — заряжается, минус — отдаёт.
    public let battery: Double
}

/// Датчики мощности SMC. Обновляются каждую секунду — в отличие от
/// телеметрии IOKit, которая отстаёт на 20–60 секунд и в момент
/// подключения или отключения адаптера отдаёт неверные значения.
///
/// Ключи (проверены на Mac16,12, macOS 27): `PDTR` — вход от адаптера,
/// `PSTR` — потребление системы, `B0AP` — мощность батареи в мВт.
/// Чтение не требует прав root.
public struct SMCPowerSensors: Sendable {
    private let smc: any SMCWriting

    /// Ниже этого порога адаптер считается не дающим питания.
    static let adapterThreshold = 0.5

    public init(smc: any SMCWriting = SMCAccess()) {
        self.smc = smc
    }

    /// nil — на этой модели нет нужных ключей или значения невалидны.
    public func read() -> PowerReading? {
        guard let adapter = smc.read("PDTR")?.floatValue,
              let system = smc.read("PSTR")?.floatValue,
              let batteryMilliwatts = smc.read("B0AP")?.signedInteger,
              (0...400).contains(adapter), (0...400).contains(system) else {
            return nil
        }

        var battery = Double(batteryMilliwatts) / 1000.0
        guard abs(battery) <= 400 else { return nil }

        // Без питания от адаптера батарея может только отдавать: знак
        // не зависит от того, как его кодирует конкретная модель.
        if adapter < Self.adapterThreshold {
            battery = -abs(battery)
        }
        return PowerReading(adapterInput: adapter, system: system,
                            battery: battery)
    }
}

public extension SMCValue {
    /// Значение типа `flt`: четыре байта, little-endian.
    var floatValue: Double? {
        guard type == "flt", bytes.count == 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Float(bitPattern: bits)
        return value.isFinite ? Double(value) : nil
    }

    /// Знаковое целое `si16` / `si32`, little-endian.
    var signedInteger: Int? {
        switch (type, bytes.count) {
        case ("si16", 2):
            return Int(Int16(bitPattern: UInt16(bytes[0]) | UInt16(bytes[1]) << 8))
        case ("si32", 4):
            return Int(Int32(bitPattern: integer))
        default:
            return nil
        }
    }
}
