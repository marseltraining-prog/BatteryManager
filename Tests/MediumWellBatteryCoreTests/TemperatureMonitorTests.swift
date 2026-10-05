import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct TemperatureMonitorTests {
    private func info(temperature: Double?) -> BatteryInfo {
        BatteryInfo(
            currentCharge: 80, maxCapacity: 4551, designCapacity: 4629,
            isCharging: true, isPluggedIn: true, voltage: 12.6, amperage: 1.0,
            temperature: temperature, cycleCount: 85,
            adapterWatts: 30.0, systemPowerWatts: 10.0, batteryPowerWatts: 5.0)
    }

    private final class StubReader: BatteryReading, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [BatteryInfo?]
        init(_ values: [BatteryInfo?]) { self.values = values }
        func getBatteryInfo() -> BatteryInfo? {
            lock.lock(); defer { lock.unlock() }
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }

    private final class RecordingController: ChargeController, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Bool] = []
        var calls: [Bool] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func setChargingAllowed(_ allowed: Bool) {
            lock.lock(); defer { lock.unlock() }
            storage.append(allowed)
        }
    }

    // MARK: - Уровни (FR-010)

    /// В начале работы сенсора ещё нет — состояние «норма», ничего не трогаем.
    @Test func initialNilTemperatureStaysNormalAndSilent() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: nil)]), controller: controller)

        monitor.evaluate()

        #expect(monitor.state == .normal)
        #expect(controller.calls.isEmpty)
    }

    @Test func justBelowWarningStaysNormal() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 34.9)]), controller: controller)

        monitor.evaluate()

        #expect(monitor.state == .normal)
        #expect(controller.calls.isEmpty)
    }

    /// FR-010 уровень 1: 35-40°C — предупреждение, заряд не трогаем.
    @Test func warningAt35DegreesDoesNotStopCharging() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 35.0)]), controller: controller)

        monitor.evaluate()

        #expect(monitor.state == .warning)
        #expect(controller.calls.isEmpty)
    }

    /// FR-010 уровень 2: выше 40°C — зарядка отключается.
    @Test func criticalTemperatureStopsCharging() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 40.1)]), controller: controller)

        monitor.evaluate()

        #expect(monitor.state == .critical)
        #expect(controller.calls == [false])
    }

    // MARK: - Возобновление заряда (FR-011)

    /// Возврат к норме (ниже 35°C) — зарядка возобновляется.
    @Test func coolingBelowWarningResumesCharging() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: 30.0)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(monitor.state == .normal)
        #expect(controller.calls == [false, true])
    }

    /// Регрессия C2: 38°C — это ещё диапазон предупреждения, не норма.
    /// Возобновлять зарядку на 38-40°C нельзя (спека: «ниже 35°C»).
    @Test func warningAfterCriticalDoesNotResumeCharging() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: 38.0)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(monitor.state == .warning)
        #expect(controller.calls == [false]) // зарядка остаётся выключенной
    }

    @Test func resumeHappensJustBelowWarningThreshold() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: 34.9)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(controller.calls == [false, true])
    }

    // MARK: - Потеря данных сенсора

    /// Регрессия C1: потеря показаний на пике не должна снимать защиту
    /// и возобновлять зарядку.
    @Test func sensorLossWhileCriticalKeepsProtection() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: nil)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(monitor.state == .critical)      // состояние сохранено
        #expect(controller.calls == [false])     // зарядка не включена
        #expect(monitor.temperature == 41.0)     // последнее известное значение
    }

    @Test func sensorLossWhileWarningKeepsState() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 37.0), info(temperature: nil)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(monitor.state == .warning)
        #expect(controller.calls.isEmpty)
    }

    @Test func callbackDoesNotFireOnSensorLoss() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: nil)]),
            controller: controller)
        var events: [TemperatureState] = []
        monitor.onStateChange = { _, new, _ in events.append(new) }

        monitor.evaluate()
        monitor.evaluate()

        #expect(events == [.critical]) // без ложного «норма» на потере сенсора
    }

    // MARK: - Уведомления о смене состояния

    @Test func callbackFiresOnlyWhenStateChanges() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([
                info(temperature: 36.0), info(temperature: 37.0),
                info(temperature: 30.0)
            ]),
            controller: controller)
        var changes: [TemperatureState] = []
        monitor.onStateChange = { _, new, _ in changes.append(new) }

        monitor.evaluate()
        monitor.evaluate()
        monitor.evaluate()

        #expect(changes == [.warning, .normal])
    }

    /// Прежнее состояние нужно, чтобы отличить нагрев от возобновления заряда.
    @Test func callbackCarriesPreviousStateAndTemperature() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 30.0), info(temperature: 41.5)]),
            controller: controller)
        var previousStates: [TemperatureState] = []
        var capturedTemperature: Double?
        monitor.onStateChange = { previous, _, temperature in
            previousStates.append(previous)
            capturedTemperature = temperature
        }

        monitor.evaluate()
        monitor.evaluate()

        #expect(previousStates == [.normal])
        #expect(capturedTemperature == 41.5)
    }

    // MARK: - Прочее

    @Test func readerFailureKeepsPreviousState() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), nil]), controller: controller)

        monitor.evaluate()
        monitor.evaluate() // сбой чтения

        #expect(monitor.state == .critical)
        #expect(controller.calls == [false])
    }

    /// Проверка по готовому снимку: приложение уже получило данные
    /// от BatteryService, повторное чтение IOKit не нужно (NFR-001).
    @Test func evaluatesFromProvidedSnapshot() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([]), controller: controller)

        monitor.evaluate(info(temperature: 41.0))

        #expect(monitor.state == .critical)
        #expect(monitor.temperature == 41.0)
        #expect(controller.calls == [false])
    }

    /// Перепутанные пороги не должны превращать 30°C в критическую температуру.
    @Test func invertedThresholdsAreNormalized() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([]), controller: controller,
            warningThreshold: 45.0, criticalThreshold: 30.0)

        monitor.evaluate(info(temperature: 35.0))

        #expect(monitor.state == .warning) // 30 < 35 < 45
        #expect(controller.calls.isEmpty)
    }
}
