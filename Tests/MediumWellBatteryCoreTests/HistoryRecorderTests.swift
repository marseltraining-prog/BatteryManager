import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct HistoryRecorderTests {
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-\(UUID().uuidString).db")
        return (try HistoryStore(databaseURL: url), url)
    }

    private let sample = BatteryInfo(
        currentCharge: 81, maxCapacity: 4551, designCapacity: 4629,
        isCharging: false, isPluggedIn: true, voltage: 12.6, amperage: 0.0,
        temperature: 27.0, cycleCount: 85, adapterWatts: 30.0,
        systemPowerWatts: 10.1, batteryPowerWatts: 0.0)

    /// Последовательный источник: по очереди, затем nil.
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

    @Test func recordNowWritesSnapshot() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try HistoryRecorder(
            reader: StubReader([sample]), store: store)

        try recorder.recordNow()

        let rows = try store.records(since: Date().addingTimeInterval(-60))
        #expect(rows.count == 1)
        #expect(rows.first?.chargePercent == 81)
    }

    /// Review Focus: нет данных сенсора/источника — запись не делается, ошибок нет.
    @Test func recordNowWritesNothingWhenReaderHasNoData() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try HistoryRecorder(reader: StubReader([nil]), store: store)
        try recorder.recordNow()

        let rows = try store.records(since: Date().addingTimeInterval(-60))
        #expect(rows.isEmpty)
    }

    @Test func pollingWritesRepeatedSnapshots() async throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try HistoryRecorder(
            reader: StubReader([sample, sample, sample, sample]),
            store: store, interval: 0.1)

        recorder.start()
        try await Task.sleep(nanoseconds: 600_000_000)
        recorder.stop()

        let rows = try store.records(since: Date().addingTimeInterval(-60))
        #expect(rows.count >= 2) // старт + тики

        recorder.stop() // повторная остановка безопасна
    }
}
