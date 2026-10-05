import Testing
@testable import MediumWellBatteryCore

@Suite
struct BatteryMetricsTests {
    let sample = BatteryInfo(
        currentCharge: 65, maxCapacity: 4800, designCapacity: 5000,
        isCharging: true, isPluggedIn: true,
        voltage: 12.0, amperage: 2.0,
        temperature: 32.0, cycleCount: 84
    )

    @Test func healthPercentageUsesMaxAndDesignCapacity() {
        #expect(sample.healthPercentage == 96)
        #expect(sample.condition == .normal)
    }

    @Test func powerWattsIsVoltageTimesAmperage() {
        #expect(abs(sample.powerWatts - 24.0) < 0.001)
    }

    @Test func temperatureStateHasWarningAndCriticalBoundaries() {
        #expect(TemperatureState(value: 34.9) == .normal)
        #expect(TemperatureState(value: 35.0) == .warning)
        #expect(TemperatureState(value: 40.0) == .warning)
        #expect(TemperatureState(value: 40.1) == .critical)
    }

    @Test func chargeLimitIsClampedToSupportedRange() {
        #expect(ChargeSettings(limit: 10).limit == 20)
        #expect(ChargeSettings(limit: 80).limit == 80)
        #expect(ChargeSettings(limit: 120).limit == 100)
    }

    @Test func batteryValuesAreClampedToSaneRanges() {
        let weird = BatteryInfo(
            currentCharge: 150, maxCapacity: -5, designCapacity: 0,
            isCharging: false, isPluggedIn: false,
            voltage: -1.0, amperage: 0.0,
            temperature: 32.0, cycleCount: -2
        )
        #expect(weird.currentCharge == 100)
        #expect(weird.maxCapacity == 0)
        #expect(weird.voltage == 0)
        #expect(weird.cycleCount == 0)
        #expect(weird.healthPercentage == 0)
    }
}
