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

    @Test func pointsMapValuesAndPreserveOrder() {
        let records = [
            record(secondsAgo: 300, charge: 80, temperature: 26.0, power: 5.0),
            record(secondsAgo: 200, charge: 81, temperature: 27.0, power: 6.0),
            record(secondsAgo: 100, charge: 82, temperature: 28.0, power: 7.0)
        ]

        let points = ChartData.points(from: records)

        #expect(points.charge.map(\.value) == [80, 81, 82])
        #expect(points.temperature.map(\.value) == [26.0, 27.0, 28.0])
        #expect(points.power.map(\.value) == [5.0, 6.0, 7.0])
    }

    /// Review Focus: нет данных температуры — точка не рисуется, но не ломает график.
    @Test func nilTemperatureIsExcluded() {
        let records = [
            record(secondsAgo: 200, charge: 80, temperature: 26.0, power: 5.0),
            record(secondsAgo: 100, charge: 81, temperature: nil, power: 6.0)
        ]

        let points = ChartData.points(from: records)

        #expect(points.temperature.count == 1)
        #expect(points.temperature.first?.value == 26.0)
        #expect(points.charge.count == 2) // заряд не зависит от температуры
    }

    @Test func emptyInputProducesEmptyPoints() {
        let points = ChartData.points(from: [])
        #expect(points.charge.isEmpty)
        #expect(points.temperature.isEmpty)
        #expect(points.power.isEmpty)
    }

    @Test func powerPointsCarryChargingFlag() {
        let now = Date()
        let records = [
            HistoryRecord(timestamp: now.addingTimeInterval(-200), chargePercent: 80,
                          temperature: nil, powerWatts: 5.0, adapterWatts: 30.0,
                          systemPowerWatts: 10.0, batteryPowerWatts: 0.0,
                          isCharging: false),
            HistoryRecord(timestamp: now.addingTimeInterval(-100), chargePercent: 81,
                          temperature: nil, powerWatts: 6.0, adapterWatts: 30.0,
                          systemPowerWatts: 10.0, batteryPowerWatts: 0.0,
                          isCharging: true)
        ]

        let points = ChartData.points(from: records)

        #expect(points.power.map(\.isCharging) == [false, true])
    }
}
