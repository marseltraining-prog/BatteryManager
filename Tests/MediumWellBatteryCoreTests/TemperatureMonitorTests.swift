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

    /// Review Focus: нет сенсора — состояние «норма», ничего не отключаем.
    @Test func nilTemperatureStaysNormalAndSilent() {
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

    /// FR-010 уровень 1: 35-40°C — только предупреждение, заряд не трогаем.
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

    /// FR-011: остывание ниже порога — зарядка возобновляется.
    @Test func coolingResumesCharging() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), info(temperature: 30.0)]),
            controller: controller)

        monitor.evaluate()
        monitor.evaluate()

        #expect(monitor.state == .normal)
        #expect(controller.calls == [false, true])
    }

    /// Уведомления только на смену состояния — иначе спам каждый опрос.
    @Test func callbackFiresOnlyWhenStateChanges() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([
                info(temperature: 36.0), info(temperature: 37.0),
                info(temperature: 30.0)
            ]),
            controller: controller)
        var changes: [TemperatureState] = []
        monitor.onStateChange = { state, _ in changes.append(state) }

        monitor.evaluate()
        monitor.evaluate()
        monitor.evaluate()

        #expect(changes == [.warning, .normal])
    }

    @Test func callbackCarriesTemperatureValue() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.5)]), controller: controller)
        var captured: Double?
        monitor.onStateChange = { _, temperature in captured = temperature }

        monitor.evaluate()

        #expect(captured == 41.5)
    }

    @Test func readerFailureKeepsPreviousState() {
        let controller = RecordingController()
        let monitor = TemperatureMonitor(
            reader: StubReader([info(temperature: 41.0), nil]), controller: controller)

        monitor.evaluate()
        monitor.evaluate() // сбой чтения

        #expect(monitor.state == .critical) // состояние не сброшено
        #expect(controller.calls == [false]) // повторно не отключаем
    }
}
