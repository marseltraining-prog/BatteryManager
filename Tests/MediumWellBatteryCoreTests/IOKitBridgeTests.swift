import Testing
@testable import MediumWellBatteryCore

@Suite
struct IOKitBridgeTests {
    /// Интеграционный тест на реальном железе: этот Mac с батареей
    /// (узлы AppleSmartBattery / AppleSmartBatteryPack в реестре IOKit).
    @Test func readsRealBatteryFromIOKit() throws {
        let info = try #require(IOKitBridge().getBatteryInfo())

        // Заряд и ёмкости (mAh): DesignCapacity ~4629, FullChargeCapacity ~4551
        #expect((0...100).contains(info.currentCharge))
        #expect(info.designCapacity > 1000)
        #expect(info.maxCapacity > 1000)
        #expect(info.healthPercentage > 50)

        // Электрика: напряжение ~12.6 В, циклы ~85
        #expect(info.voltage > 10.0 && info.voltage < 13.5)
        #expect(info.cycleCount >= 0)
        #expect(info.condition == .normal)

        // Температура из AppleSmartBatteryPack: ~27°C.
        // Диапазон 10...45 ловит ошибку масштаба (сырые 2700 или 2.7).
        let temperature = try #require(info.temperature)
        #expect(temperature > 10.0 && temperature < 45.0)

        // Адаптер подключён: ~30 W (если данные есть).
        if let adapterWatts = info.adapterWatts {
            #expect(adapterWatts > 0)
        }
        // Потребление системы из PowerTelemetryData: >= 0 (если есть).
        if let systemPowerWatts = info.systemPowerWatts {
            #expect(systemPowerWatts >= 0)
        }
    }

    /// Нормализация сырой температуры pack (сотые доли °C) с валидацией
    /// диапазона по Review Focus: невалидные значения → nil.
    @Test func normalizesPackTemperatureAndRejectsInvalid() {
        #expect(IOKitBridge.normalizedTemperature(2700) == 27.0)
        #expect(IOKitBridge.normalizedTemperature(3850) == 38.5)
        #expect(IOKitBridge.normalizedTemperature(-300) == -3.0)
        #expect(IOKitBridge.normalizedTemperature(nil) == nil)
        #expect(IOKitBridge.normalizedTemperature(20000) == nil) // 200°C — невалидно
        #expect(IOKitBridge.normalizedTemperature(-5000) == nil) // -50°C — невалидно
    }
}
