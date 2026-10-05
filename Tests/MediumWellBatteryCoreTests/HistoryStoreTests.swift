import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct HistoryStoreTests {
    /// Уникальная временная база на каждый тест.
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).db")
        let store = try HistoryStore(databaseURL: url)
        return (store, url)
    }

    private func sampleInfo(
        charge: Int = 81, temperature: Double? = 27.0, power: Double = 0.0,
        adapter: Double? = 30.0, system: Double? = 10.1, battery: Double? = 0.0,
        charging: Bool = false
    ) -> BatteryInfo {
        BatteryInfo(
            currentCharge: charge, maxCapacity: 4551, designCapacity: 4629,
            isCharging: charging, isPluggedIn: adapter != nil,
            voltage: 12.6, amperage: 0.0, temperature: temperature,
            cycleCount: 85, adapterWatts: adapter, systemPowerWatts: system,
            batteryPowerWatts: battery)
    }

    @Test func recordThenReadRoundtrip() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(), at: date)

        let records = try store.records(since: date.addingTimeInterval(-1))
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.chargePercent == 81)
        #expect(record.temperature == 27.0)
        #expect(record.powerWatts == 0.0)
        #expect(record.adapterWatts == 30.0)
        #expect(record.systemPowerWatts == 10.1)
        #expect(record.batteryPowerWatts == 0.0)
        #expect(record.isCharging == false)
        #expect(record.timestamp == date)
    }

    @Test func nilTemperatureIsStoredAndReadBackAsNil() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let date = Date()
        try store.record(sampleInfo(temperature: nil), at: date)

        let record = try #require(try store.records(since: date.addingTimeInterval(-1)).first)
        #expect(record.temperature == nil)
    }

    @Test func recordsAreOrderedByTimestampAscending() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(charge: 80), at: base)
        try store.record(sampleInfo(charge: 81), at: base.addingTimeInterval(60))
        try store.record(sampleInfo(charge: 82), at: base.addingTimeInterval(120))

        let records = try store.records(since: base.addingTimeInterval(-1))
        #expect(records.map(\.chargePercent) == [80, 81, 82])
    }

    @Test func recordsSinceFiltersOlderRows() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(charge: 80), at: base)
        try store.record(sampleInfo(charge: 85), at: base.addingTimeInterval(3600))

        let recent = try store.records(since: base.addingTimeInterval(1800))
        #expect(recent.map(\.chargePercent) == [85])
    }

    @Test func pruneRemovesOnlyOldRows() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date()
        let old = now.addingTimeInterval(-48 * 3600) // 48 часов назад
        try store.record(sampleInfo(charge: 50), at: old)
        try store.record(sampleInfo(charge: 85), at: now)

        try store.prune(olderThan: 24 * 3600, from: now)

        let records = try store.records(since: old.addingTimeInterval(-1))
        #expect(records.map(\.chargePercent) == [85])
    }

    /// Review Focus: повреждённая база — пересоздать, не падать.
    @Test func corruptDatabaseIsRecreated() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a sqlite database at all".utf8).write(to: url)

        let store = try HistoryStore(databaseURL: url)
        try store.record(sampleInfo(), at: Date())
        let records = try store.records(since: Date().addingTimeInterval(-60))
        #expect(records.count == 1)
    }
}
