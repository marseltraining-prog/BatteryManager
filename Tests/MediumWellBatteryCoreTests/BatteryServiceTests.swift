import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct BatteryServiceTests {
    private let sample = BatteryInfo(
        currentCharge: 81, maxCapacity: 4551, designCapacity: 4629,
        isCharging: false, isPluggedIn: true,
        voltage: 12.6, amperage: 0.0,
        temperature: 27.0, cycleCount: 85,
        adapterWatts: 30.0, systemPowerWatts: 10.1, batteryPowerWatts: 0.0
    )

    /// Последовательный источник-заглушка: отдаёт значения по очереди,
    /// затем nil — имитация сбоя IOKit или пропавшей батареи.
    private final class StubReader: BatteryReading, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [BatteryInfo?]

        init(_ values: [BatteryInfo?]) { self.values = values }

        func getBatteryInfo() -> BatteryInfo? {
            lock.lock()
            defer { lock.unlock() }
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }

    @Test func refreshPublishesDataFromReader() {
        let service = BatteryService(bridge: StubReader([sample]))
        service.refresh()
        #expect(service.currentData == sample)
    }

    /// Review Focus: сбой чтения — держим последние валидные данные.
    @Test func refreshKeepsLastValidDataWhenReaderFails() {
        let service = BatteryService(bridge: StubReader([sample, nil]))
        service.refresh()
        service.refresh() // nil — имитация сбоя
        #expect(service.currentData == sample)
    }

    @Test func refreshWithRealBridgeReadsThisMac() throws {
        let service = BatteryService(bridge: IOKitBridge())
        service.refresh()
        let info = try #require(service.currentData)
        #expect((0...100).contains(info.currentCharge))
    }

    /// Первый опрос возвращает nil — данные могут появиться только
    /// от тика таймера: так проверяется сам периодический опрос.
    @Test func monitoringPollsUntilStopped() async throws {
        let service = BatteryService(bridge: StubReader([nil, sample]),
                                     updateInterval: 0.1)
        service.startMonitoring()
        #expect(service.isMonitoring)
        #expect(service.currentData == nil)

        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(service.currentData == sample)

        service.stopMonitoring()
        #expect(!service.isMonitoring)
    }
}
