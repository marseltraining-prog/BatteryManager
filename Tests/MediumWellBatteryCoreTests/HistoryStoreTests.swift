import Foundation
import SQLite3
import Testing
@testable import MediumWellBatteryCore

@Suite
struct HistoryStoreTests {
    /// Временная база с уборкой всех файлов (включая WAL и SHM).
    private func makeStore() throws -> (HistoryStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).db")
        return (try HistoryStore(databaseURL: url), url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func sampleInfo(
        charge: Int = 81, temperature: Double? = 27.0,
        voltage: Double = 12.6, amperage: Double = 2.0,
        charging: Bool = true, adapter: Double? = 30.0,
        system: Double? = 10.1, battery: Double? = 0.0
    ) -> BatteryInfo {
        BatteryInfo(
            currentCharge: charge, maxCapacity: 4551, designCapacity: 4629,
            isCharging: charging, isPluggedIn: adapter != nil,
            voltage: voltage, amperage: amperage, temperature: temperature,
            cycleCount: 85, adapterWatts: adapter, systemPowerWatts: system,
            batteryPowerWatts: battery)
    }

    @Test func recordThenReadRoundtrip() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(), at: date)

        let records = try store.records(since: date.addingTimeInterval(-1))
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.chargePercent == 81)
        #expect(record.temperature == 27.0)
        #expect(record.adapterWatts == 30.0)
        #expect(record.systemPowerWatts == 10.1)
        #expect(record.batteryPowerWatts == 0.0)
        #expect(record.isCharging == true)
        #expect(record.timestamp == date)
    }

    /// Мощность хранится со знаком (FR-009): 12.6 В × 2 А = 25.2 Вт при зарядке.
    @Test func powerIsStoredWithSign() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let date = Date()
        try store.record(sampleInfo(voltage: 12.6, amperage: 2.0, charging: true),
                         at: date)
        try store.record(sampleInfo(voltage: 12.6, amperage: -2.0, charging: false,
                                    adapter: nil),
                         at: date.addingTimeInterval(1))

        let records = try store.records(since: date.addingTimeInterval(-1))
        #expect(records.count == 2)
        #expect(abs((records[0].powerWatts) - 25.2) < 0.001)
        #expect(abs((records[1].powerWatts) + 25.2) < 0.001)
    }

    @Test func nilTemperatureIsStoredAndReadBackAsNil() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let date = Date()
        try store.record(sampleInfo(temperature: nil), at: date)

        let record = try #require(
            try store.records(since: date.addingTimeInterval(-1)).first)
        #expect(record.temperature == nil)
    }

    @Test func recordsAreOrderedByTimestampAscending() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(charge: 80), at: base)
        try store.record(sampleInfo(charge: 81), at: base.addingTimeInterval(60))
        try store.record(sampleInfo(charge: 82), at: base.addingTimeInterval(120))

        let records = try store.records(since: base.addingTimeInterval(-1))
        #expect(records.map(\.chargePercent) == [80, 81, 82])
    }

    @Test func recordsSinceFiltersOlderRows() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(sampleInfo(charge: 80), at: base)
        try store.record(sampleInfo(charge: 85), at: base.addingTimeInterval(3600))

        let recent = try store.records(since: base.addingTimeInterval(1800))
        #expect(recent.map(\.chargePercent) == [85])
    }

    /// Повторная запись на тот же момент времени не теряет снимок.
    @Test func duplicateTimestampReplacesPreviousRecord() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let date = Date()
        try store.record(sampleInfo(charge: 80), at: date)
        try store.record(sampleInfo(charge: 90), at: date)

        let records = try store.records(since: date.addingTimeInterval(-60))
        #expect(records.count == 1)
        #expect(records.first?.chargePercent == 90)
    }

    @Test func pruneRemovesOnlyOldRows() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let now = Date()
        let old = now.addingTimeInterval(-48 * 3600)
        try store.record(sampleInfo(charge: 50), at: old)
        try store.record(sampleInfo(charge: 85), at: now)

        try store.prune(olderThan: 24 * 3600, from: now)

        let records = try store.records(since: old.addingTimeInterval(-1))
        #expect(records.map(\.chargePercent) == [85])
    }

    /// Освобождение места: удаляется самая старая половина записей.
    @Test func pruneOldestRemovesOldestFraction() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<10 {
            try store.record(sampleInfo(charge: 50 + index),
                             at: base.addingTimeInterval(Double(index)))
        }

        let removed = try store.pruneOldest(fraction: 0.5)

        #expect(removed == 5)
        let remaining = try store.records(since: base.addingTimeInterval(-1))
        #expect(remaining.map(\.chargePercent) == [55, 56, 57, 58, 59])
    }

    /// Review Focus: заполненный диск — история урезается вдвое и запись
    /// повторяется. Размер базы ограничивается принудительно (SQLITE_FULL).
    @Test func diskFullPrunesHistoryAndRetriesWrite() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        // В режиме DELETE рост упирается в max_page_count (в WAL — нет).
        try store.setJournalModeForTesting("DELETE")

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<40 {
            try store.record(sampleInfo(charge: 40 + index),
                             at: base.addingTimeInterval(Double(index)))
        }
        let filled = try store.count()
        #expect(filled == 40)

        // Запрещаем базе расти и убеждаемся, что ошибка действительно
        // возникает: одна вставка без политики восстановления падает.
        try store.setMaxPageCount(try store.pageCount())

        var fullError: HistoryStoreError?
        for index in 0..<10_000 {
            do {
                try store.insertOnceForTesting(
                    sampleInfo(charge: 90),
                    at: base.addingTimeInterval(1000 + Double(index)))
            } catch let error as HistoryStoreError {
                fullError = error
                break
            }
        }
        #expect(fullError?.isDiskFull == true)

        // А теперь обычная запись: она обязана пройти, освободив место
        // (сколько именно строк удалось удалить, зависит от того, сколько
        // свободного места вернул откат неудачной вставки).
        try store.record(sampleInfo(charge: 99), at: base.addingTimeInterval(2000))

        let records = try store.records(since: base.addingTimeInterval(-1))
        #expect(records.contains { $0.chargePercent == 99 })

        // База осталась рабочей: следующая запись тоже проходит.
        try store.record(sampleInfo(charge: 98), at: base.addingTimeInterval(2001))
        #expect(try store.records(since: base.addingTimeInterval(-1)).count
            == records.count + 1)
    }

    /// Review Focus: мусор в файле — база пересоздаётся, приложение работает.
    @Test func corruptDatabaseIsRecreated() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).db")
        defer { cleanup(url) }
        try Data("not a sqlite database at all".utf8).write(to: url)

        let store = try HistoryStore(databaseURL: url)
        try store.record(sampleInfo(), at: Date())

        #expect(try store.count() == 1)
    }

    /// Повреждение, найденное не при открытии, а при записи: база
    /// пересоздаётся, и запись проходит.
    @Test func corruptionDetectedAtWriteTimeIsRecovered() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        try store.record(sampleInfo(charge: 80), at: Date())
        #expect(try store.count() == 1)

        // Портим страницу данных, оставив заголовок корректным.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 4096 * 2)
        try handle.write(contentsOf: Data(repeating: 0x00, count: 512))
        try handle.close()

        // База уже открыта, поэтому повреждение проявится на запросе.
        let recovered = (try? store.records(since: Date().addingTimeInterval(-60)))
        #expect(recovered != nil) // чтение не падает и не врёт молча

        try store.record(sampleInfo(charge: 77), at: Date())
        #expect(try store.records(since: Date().addingTimeInterval(-60)).count >= 1)
    }

    /// Записи WAL и SHM удаляются вместе с базой — иначе старые страницы
    /// «воскресают» при пересоздании.
    @Test func recoveryRemovesWalSidecars() throws {
        let (store, url) = try makeStore()
        defer { cleanup(url) }

        for index in 0..<20 {
            try store.record(sampleInfo(charge: 30 + index),
                             at: Date().addingTimeInterval(Double(index)))
        }

        let garbage = Data("broken".utf8)
        try garbage.write(to: URL(fileURLWithPath: url.path + "-wal"))

        // Повреждение основного файла → пересоздание вместе с журналом.
        try garbage.write(to: url)
        let fresh = try HistoryStore(databaseURL: url)

        #expect(try fresh.count() == 0)
    }

    @Test func errorCodesAreClassified() {
        #expect(HistoryStoreError.writeFailed(code: SQLITE_FULL, message: "").isDiskFull)
        #expect(HistoryStoreError.writeFailed(
            code: SQLITE_FULL | (1 << 8), message: "").isDiskFull)
        #expect(HistoryStoreError.readFailed(code: SQLITE_CORRUPT, message: "").isCorrupt)
        #expect(HistoryStoreError.openFailed(code: SQLITE_NOTADB, message: "").isCorrupt)
        #expect(!HistoryStoreError.writeFailed(code: SQLITE_BUSY, message: "").isDiskFull)
        #expect(!HistoryStoreError.writeFailed(code: SQLITE_BUSY, message: "").isCorrupt)
    }

    /// Ошибка должна нести понятное описание (NFR-004).
    @Test func errorsHaveReadableDescription() {
        let error = HistoryStoreError.writeFailed(
            code: SQLITE_FULL, message: "database or disk is full")
        #expect(error.errorDescription?.contains("disk is full") == true)
    }
}
