import Foundation

/// Точки для графиков Swift Charts. Отдельные типы — чтобы оси и
/// форматирование у каждого графика были свои (DESIGN.md).
public struct ChargePoint: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Int
}

public struct TemperaturePoint: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Double
}

public struct PowerPoint: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public let isCharging: Bool
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

    /// Преобразует записи истории в точки графиков, сохраняя порядок.
    /// Записи без данных температуры дают точку заряда/мощности,
    /// но не дают точки температуры (Review Focus: пробелы в графике).
    public static func points(from records: [HistoryRecord]) -> ChartData {
        ChartData(
            charge: records.map {
                ChargePoint(date: $0.timestamp, value: $0.chargePercent)
            },
            temperature: records.compactMap { record in
                record.temperature.map {
                    TemperaturePoint(date: record.timestamp, value: $0)
                }
            },
            power: records.map {
                PowerPoint(date: $0.timestamp, value: $0.powerWatts,
                           isCharging: $0.isCharging)
            }
        )
    }
}
