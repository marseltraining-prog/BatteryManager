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
        // Нет данных о ёмкости — состояние неизвестно, а не «к обслуживанию».
        #expect(weird.condition == .unknown)
    }

    // MARK: - Знак мощности (FR-009)

    @Test func chargingDrawsPositivePower() {
        #expect(sample.powerWatts > 0)
        #expect(abs(sample.powerWatts - 24.0) < 0.001)
    }

    @Test func dischargingReportsNegativePower() {
        let discharging = BatteryInfo(
            currentCharge: 80, maxCapacity: 4551, designCapacity: 4629,
            isCharging: false, isPluggedIn: false,
            voltage: 12.6, amperage: -1.5,
            temperature: 30.0, cycleCount: 85)

        #expect(discharging.powerWatts < 0)
        #expect(abs(discharging.powerWatts + 18.9) < 0.001)
    }

    /// Подключён, но заряд не идёт и ток нулевой — потребления нет.
    @Test func pluggedIdleReportsZeroPower() {
        let idle = BatteryInfo(
            currentCharge: 85, maxCapacity: 4551, designCapacity: 4629,
            isCharging: false, isPluggedIn: true,
            voltage: 12.6, amperage: 0.0,
            temperature: 27.0, cycleCount: 85)

        #expect(idle.powerWatts == 0)
    }

    // MARK: - Границы здоровья

    @Test func conditionReflectsHealthBands() {
        func condition(max: Int, design: Int) -> BatteryCondition {
            BatteryInfo(currentCharge: 50, maxCapacity: max, designCapacity: design,
                        isCharging: false, isPluggedIn: false,
                        voltage: 12.0, amperage: 0.0,
                        temperature: 27.0, cycleCount: 10).condition
        }

        #expect(condition(max: 4629, design: 4629) == .normal)      // 100%
        #expect(condition(max: 3900, design: 4629) == .normal)      // 84%
        #expect(condition(max: 3200, design: 4629) == .replaceSoon) // 69%
        #expect(condition(max: 2500, design: 4629) == .serviceBattery) // 54%
    }

    /// Абсурдная ёмкость не должна ломать преобразование в Int.
    @Test func absurdCapacityDoesNotCrash() {
        let absurd = BatteryInfo(
            currentCharge: 50, maxCapacity: Int.max, designCapacity: 1,
            isCharging: false, isPluggedIn: false,
            voltage: 12.0, amperage: 0.0, temperature: 27.0, cycleCount: 1)

        #expect(absurd.healthPercentage == 100)
    }

    @Test func percentOfDesignUsesDesignCapacity() {
        let info = BatteryInfo(
            currentCharge: 80, maxCapacity: 4486, designCapacity: 4629,
            isCharging: false, isPluggedIn: false, voltage: 12, amperage: 0,
            temperature: nil, cycleCount: 85, nominalCapacity: 4613)
        #expect(info.percentOfDesign(4486) == 97)
        #expect(info.percentOfDesign(4613) == 100)
        #expect(info.nominalCapacity == 4613)
    }

    @Test func percentOfDesignIsNilWithoutDesignCapacity() {
        let info = BatteryInfo(
            currentCharge: 80, maxCapacity: 4486, designCapacity: 0,
            isCharging: false, isPluggedIn: false, voltage: 12, amperage: 0,
            temperature: nil, cycleCount: 85, nominalCapacity: 0)
        #expect(info.percentOfDesign(4486) == nil)
        #expect(info.nominalCapacity == nil)
    }
}
