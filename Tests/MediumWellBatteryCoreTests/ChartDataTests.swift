import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct ChartDataTests {
    private func record(
        secondsAgo: TimeInterval, charge: Int, temperature: Double?,
        power: Double, charging: Bool = false
    ) -> HistoryRecord {
        HistoryRecord(
            timestamp: Date().addingTimeInterval(-secondsAgo),
            chargePercent: charge, temperature: temperature,
            powerWatts: power, adapterWatts: 30.0, systemPowerWatts: 10.0,
            batteryPowerWatts: 0.0, isCharging: charging)
    }

    private func record(
        at date: Date, charge: Int, temperature: Double? = 27.0,
        power: Double = 0.0, charging: Bool = false
    ) -> HistoryRecord {
        HistoryRecord(
            timestamp: date, chargePercent: charge, temperature: temperature,
            powerWatts: power, adapterWatts: 30.0, systemPowerWatts: 10.0,
            batteryPowerWatts: 0.0, isCharging: charging)
    }

    @Test func pointsMapValuesAndPreserveOrder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            record(at: base, charge: 80, temperature: 26.0, power: 5.0),
            record(at: base.addingTimeInterval(60), charge: 81, temperature: 27.0, power: 6.0),
            record(at: base.addingTimeInterval(120), charge: 82, temperature: 28.0, power: 7.0)
        ]

        let points = ChartData.points(from: records)

        #expect(points.charge.map(\.value) == [80, 81, 82])
        #expect(points.temperature.map(\.value) == [26.0, 27.0, 28.0])
        #expect(points.power.map(\.value) == [5.0, 6.0, 7.0])
    }

    /// Review Focus: нет данных температуры — точка не рисуется,
    /// но не ломает остальные графики.
    @Test func nilTemperatureIsExcluded() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            record(at: base, charge: 80, temperature: 26.0, power: 5.0),
            record(at: base.addingTimeInterval(60), charge: 81, temperature: nil, power: 6.0)
        ]

        let points = ChartData.points(from: records)

        #expect(points.temperature.count == 1)
        #expect(points.temperature.first?.value == 26.0)
        #expect(points.charge.count == 2)
    }

    @Test func emptyInputProducesEmptyPoints() {
        let points = ChartData.points(from: [])
        #expect(points.charge.isEmpty)
        #expect(points.temperature.isEmpty)
        #expect(points.power.isEmpty)
    }

    @Test func powerPointsCarryChargingFlag() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            record(at: base, charge: 80, temperature: nil, power: -5.0, charging: false),
            record(at: base.addingTimeInterval(60), charge: 81, temperature: nil,
                   power: 6.0, charging: true)
        ]

        let points = ChartData.points(from: records)

        #expect(points.power.map(\.isCharging) == [false, true])
        #expect(points.power.map(\.value) == [-5.0, 6.0])
    }

    // MARK: - Разрывы истории (сон)

    /// Непрерывные записи (раз в минуту) — одна серия.
    @Test func continuousRecordsShareOneSegment() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = (0..<5).map { index in
            record(at: base.addingTimeInterval(Double(index) * 60),
                   charge: 80 + index)
        }

        let points = ChartData.points(from: records)

        #expect(points.charge.allSatisfy { $0.segment == 0 })
    }

    /// Пропуск (например, Mac спал 8 часов) разрывает линию:
    /// иначе график нарисовал бы несуществующий плавный переход.
    @Test func gapStartsNewSegment() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            record(at: base, charge: 80),
            record(at: base.addingTimeInterval(60), charge: 81),
            record(at: base.addingTimeInterval(8 * 3600), charge: 60), // сон
            record(at: base.addingTimeInterval(8 * 3600 + 60), charge: 59)
        ]

        let points = ChartData.points(from: records)

        #expect(points.charge.map(\.segment) == [0, 0, 1, 1])
        #expect(points.temperature.map(\.segment) == [0, 0, 1, 1])
    }

    /// Точки одного момента времени равны — SwiftUI не пересоздаёт их зря.
    @Test func pointsFromSameRecordsAreEqual() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [record(at: base, charge: 80), record(at: base.addingTimeInterval(60), charge: 81)]

        #expect(ChartData.points(from: records) == ChartData.points(from: records))
        #expect(ChartData.points(from: records).charge.first?.id == base)
    }
}
