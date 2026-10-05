import Foundation
import SQLite3

/// Одна запись истории батареи (снимок на момент времени).
public struct HistoryRecord: Equatable, Sendable {
    public let timestamp: Date
    public let chargePercent: Int
    public let temperature: Double?
    public let powerWatts: Double
    public let adapterWatts: Double?
    public let systemPowerWatts: Double?
    public let batteryPowerWatts: Double?
    public let isCharging: Bool

    public init(timestamp: Date, chargePercent: Int, temperature: Double?,
                powerWatts: Double, adapterWatts: Double?,
                systemPowerWatts: Double?, batteryPowerWatts: Double?,
                isCharging: Bool) {
        self.timestamp = timestamp
        self.chargePercent = chargePercent
        self.temperature = temperature
        self.powerWatts = powerWatts
        self.adapterWatts = adapterWatts
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.isCharging = isCharging
    }
}

/// Хранилище истории батареи на системном SQLite3 (WAL).
/// Схема: таблица battery_history, по строке на снимок.
/// Повреждённая база пересоздаётся (Review Focus), а не роняет приложение.
public final class HistoryStore: Sendable {
    private let databaseURL: URL
    private let lock = NSLock()

    /// Инициализация выполняется один раз; дальше доступ под lock.
    private nonisolated(unsafe) var handle: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        try open()
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    /// Путь базы по умолчанию: ~/Library/Application Support/BatteryManager/history.db
    public static func defaultDatabaseURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("BatteryManager", isDirectory: true)
            .appendingPathComponent("history.db")
    }

    // MARK: - Запись / чтение

    /// Сохраняет снимок данных батареи.
    public func record(_ info: BatteryInfo, at date: Date = Date()) throws {
        let sql = """
            INSERT INTO battery_history
            (timestamp, charge_percent, temperature, power_watts,
             adapter_watts, system_power_watts, battery_power_watts, is_charging)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(info.currentCharge))
            if let temperature = info.temperature {
                sqlite3_bind_double(statement, 3, temperature)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_double(statement, 4, info.powerWatts)
            bindOptional(statement, 5, info.adapterWatts)
            bindOptional(statement, 6, info.systemPowerWatts)
            bindOptional(statement, 7, info.batteryPowerWatts)
            sqlite3_bind_int(statement, 8, info.isCharging ? 1 : 0)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.writeFailed(lastError(statement))
            }
        }
    }

    /// Записи за период, по возрастанию времени.
    public func records(since date: Date) throws -> [HistoryRecord] {
        let sql = """
            SELECT timestamp, charge_percent, temperature, power_watts,
                   adapter_watts, system_power_watts, battery_power_watts, is_charging
            FROM battery_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
        return try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            var result: [HistoryRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
                let charge = Int(sqlite3_column_int(statement, 1))
                let temperature = sqlite3_column_type(statement, 2) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 2)
                let power = sqlite3_column_double(statement, 3)
                let adapter = optionalDouble(statement, 4)
                let system = optionalDouble(statement, 5)
                let battery = optionalDouble(statement, 6)
                let charging = sqlite3_column_int(statement, 7) == 1
                result.append(HistoryRecord(
                    timestamp: timestamp, chargePercent: charge,
                    temperature: temperature, powerWatts: power,
                    adapterWatts: adapter, systemPowerWatts: system,
                    batteryPowerWatts: battery, isCharging: charging))
            }
            return result
        }
    }

    /// Удаляет записи старше `olderThan` секунд от момента `from`.
    public func prune(olderThan: TimeInterval, from date: Date = Date()) throws {
        let cutoff = date.addingTimeInterval(-olderThan)
        let sql = "DELETE FROM battery_history WHERE timestamp < ?;"
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.writeFailed(lastError(statement))
            }
        }
    }

    // MARK: - SQLite

    private func open() throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        // Review Focus: повреждённая база — удалить файл и пересоздать.
        do {
            try openHandle(flags: flags)
            try createSchema()
        } catch {
            closeHandle()
            try? FileManager.default.removeItem(at: databaseURL)
            try openHandle(flags: flags)
            try createSchema()
        }
    }

    private func openHandle(flags: Int32) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close_v2(db) }
            throw HistoryStoreError.openFailed("не удалось открыть базу")
        }
        handle = db
    }

    private func closeHandle() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    /// WAL: надёжность и параллельное чтение.
    private func createSchema() throws {
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS battery_history (
                timestamp REAL PRIMARY KEY,
                charge_percent INTEGER NOT NULL,
                temperature REAL,
                power_watts REAL NOT NULL,
                adapter_watts REAL,
                system_power_watts REAL,
                battery_power_watts REAL,
                is_charging INTEGER NOT NULL
            );
            """)
    }

    /// Review Focus: повреждённая база — удалить файл и пересоздать.
    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw HistoryStoreError.writeFailed(message)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.writeFailed(lastError(nil))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func lastError(_ statement: OpaquePointer?) -> String {
        let message = sqlite3_errmsg(handle).map { String(cString: $0) } ?? "unknown"
        return message
    }

    private func bindOptional(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil : sqlite3_column_double(statement, index)
    }
}

public enum HistoryStoreError: Error, Equatable {
    case openFailed(String)
    case writeFailed(String)
}
