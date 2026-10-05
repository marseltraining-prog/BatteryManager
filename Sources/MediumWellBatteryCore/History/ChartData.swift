import Foundation

/// Точка графика заряда. `segment` разделяет разрывы истории (сон,
/// выключение) — линия не должна соединять данные через пропуск.
public struct ChargePoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Int
    public let segment: Int
}

public struct TemperaturePoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Double
    public let segment: Int
}

public struct PowerPoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Double
    public let isCharging: Bool
    public let segment: Int
}

/// Точки трёх графиков за период истории.
public struct ChartData: Equatable, Sendable {
    public let charge: [ChargePoint]
    public let temperature: [TemperaturePoint]
    public let power: [PowerPoint]

    public init(charge: [ChargePoint], temperature: [TemperaturePoint],
                power: [PowerPoint]) {
        self.charge = charge
        self.temperature = temperature
        self.power = power
    }

    /// Разрыв истории: запись реже, чем 1.5 периода записи (60 с).
    /// Например, Mac спал — соединять линию через этот промежуток нельзя.
    public static let defaultGapTolerance: TimeInterval = 90

    /// Преобразует записи истории в точки графиков, сохраняя порядок
    /// и разрывая линию на пропусках (NFR-006).
    public static func points(
        from records: [HistoryRecord],
        gapTolerance: TimeInterval = defaultGapTolerance
    ) -> ChartData {
        var charge: [ChargePoint] = []
        var temperature: [TemperaturePoint] = []
        var power: [PowerPoint] = []

        var segment = 0
        var previousDate: Date?

        for record in records {
            if let previousDate,
               record.timestamp.timeIntervalSince(previousDate) > gapTolerance {
                segment += 1
            }
            previousDate = record.timestamp

            charge.append(ChargePoint(date: record.timestamp,
                                      value: record.chargePercent,
                                      segment: segment))
            power.append(PowerPoint(date: record.timestamp,
                                    value: record.powerWatts,
                                    isCharging: record.isCharging,
                                    segment: segment))
            if let value = record.temperature {
                temperature.append(TemperaturePoint(date: record.timestamp,
                                                    value: value,
                                                    segment: segment))
            }
        }

        return ChartData(charge: charge, temperature: temperature, power: power)
    }
}
