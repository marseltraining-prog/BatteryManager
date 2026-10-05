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

/// Ошибки хранилища с кодом SQLite: по коду принимаются решения
/// (заполнен диск → освободить место; повреждение → пересоздать базу).
public enum HistoryStoreError: Error, Equatable, LocalizedError {
    case openFailed(code: Int32, message: String)
    case writeFailed(code: Int32, message: String)
    case readFailed(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(_, let message):
            return "Не удалось открыть историю батареи: \(message)"
        case .writeFailed(_, let message):
            return "Не удалось записать историю батареи: \(message)"
        case .readFailed(_, let message):
            return "Не удалось прочитать историю батареи: \(message)"
        }
    }

    public var code: Int32 {
        switch self {
        case .openFailed(let code, _),
             .writeFailed(let code, _),
             .readFailed(let code, _):
            return code
        }
    }

    /// Основной код SQLite без расширенных битов.
    private var primaryCode: Int32 { code & 0xFF }

    /// SQLITE_IOERR_SHORT_READ: журнал WAL оборван (недописанные страницы
    /// после сбоя). Не все SDK экспортируют это имя, поэтому считаем сами.
    private static let ioerrShortRead: Int32 = SQLITE_IOERR | (2 << 8)

    /// На диске закончилось место.
    public var isDiskFull: Bool { primaryCode == SQLITE_FULL }

    /// Файл повреждён, это вообще не база данных или журнал оборван
    /// (недописанные страницы WAL после сбоя) — во всех этих случаях
    /// базу можно безопасно пересоздать.
    ///
    /// Обычный `SQLITE_IOERR` сюда НЕ входит: это может быть отказ диска
    /// или проблема прав, и удалять историю пользователя в этом случае нельзя.
    public var isCorrupt: Bool {
        primaryCode == SQLITE_CORRUPT
            || primaryCode == SQLITE_NOTADB
            || code == Self.ioerrShortRead
    }
}

/// Хранилище истории батареи на системном SQLite3 (WAL).
///
/// Устойчивость (Review Focus):
/// - заполнен диск — освобождаем половину истории и пробуем записать снова;
/// - база повреждена — пересоздаём её (вместе с `-wal`/`-shm`) и продолжаем;
/// - ошибки чтения не подменяются пустым результатом.
public final class HistoryStore: Sendable {
    private let databaseURL: URL
    private let lock = NSLock()
    private nonisolated(unsafe) var handle: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        try open()
    }

    deinit {
        closeHandle()
    }

    /// Путь базы по умолчанию:
    /// ~/Library/Application Support/BatteryManager/history.db
    public static func defaultDatabaseURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("BatteryManager", isDirectory: true)
            .appendingPathComponent("history.db")
    }

    // MARK: - Запись

    /// Сохраняет снимок данных батареи.
    public func record(_ info: BatteryInfo, at date: Date = Date()) throws {
        do {
            try insert(info, at: date)
        } catch let error as HistoryStoreError {
            // Review Focus: диск заполнен — освобождаем половину истории
            // и пробуем ещё раз (единственная повторная попытка).
            if error.isDiskFull {
                // Освобождаем половину истории и пробуем ещё раз.
                // Ошибку очистки логируем: даже если она не удалась,
                // повторная вставка может пройти за счёт отката.
                do {
                    try pruneOldest(fraction: 0.5)
                } catch {
                    NSLog("BatteryManager: не удалось освободить историю: %@",
                          String(describing: error))
                }
                try insert(info, at: date)
            } else if error.isCorrupt {
                // Повреждение может проявиться уже после открытия базы.
                try recover()
                try insert(info, at: date)
            } else {
                throw error
            }
        }
    }

    // MARK: - Чтение

    /// Записи за период, по возрастанию времени.
    /// Ошибки SQLite пробрасываются: пустой график не должен скрывать сбой.
    public func records(since date: Date) throws -> [HistoryRecord] {
        let sql = """
            SELECT timestamp, charge_percent, temperature, power_watts,
                   adapter_watts, system_power_watts, battery_power_watts, is_charging
            FROM battery_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC;
            """
        return try readWithRecovery(sql) { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        } body: { statement in
            var result: [HistoryRecord] = []
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                let timestamp = Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 0))
                let charge = Int(sqlite3_column_int(statement, 1))
                let temperature: Double? =
                    sqlite3_column_type(statement, 2) == SQLITE_NULL
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

                stepResult = sqlite3_step(statement)
            }

            guard stepResult == SQLITE_DONE else {
                throw HistoryStoreError.readFailed(
                    code: sqlite3_extended_errcode(handle),
                    message: lastError())
            }
            return result
        }
    }

    /// Количество записей (диагностика и тесты).
    public func count() throws -> Int {
        try readWithRecovery("SELECT COUNT(*) FROM battery_history;",
                             bind: { _ in }) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw HistoryStoreError.readFailed(
                    code: sqlite3_extended_errcode(handle), message: lastError())
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    // MARK: - Очистка

    /// Удаляет записи старше `olderThan` секунд от момента `from`.
    public func prune(olderThan: TimeInterval, from date: Date = Date()) throws {
        let cutoff = date.addingTimeInterval(-olderThan)
        try execute("DELETE FROM battery_history WHERE timestamp < ?;") {
            sqlite3_bind_double($0, 1, cutoff.timeIntervalSince1970)
        }
    }

    /// Удаляет самую старую долю записей (0...1) — освобождение места.
    @discardableResult
    public func pruneOldest(fraction: Double) throws -> Int {
        let bounded = min(max(fraction, 0.0), 1.0)
        let sql = """
            DELETE FROM battery_history WHERE timestamp IN (
                SELECT timestamp FROM battery_history
                ORDER BY timestamp ASC
                LIMIT MAX(1, CAST((SELECT COUNT(*) FROM battery_history) * ? AS INTEGER))
            );
            """
        return try execute(sql) { statement in
            sqlite3_bind_double(statement, 1, bounded)
        }
    }

    // MARK: - SQLite

    private func open() throws {
        // Недописанную транзакцию WAL нужно уметь продолжить.
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        do {
            try openHandle(flags: flags)
            try createSchema()
        } catch let error as HistoryStoreError where error.isCorrupt {
            // Повреждённый файл: удаляем всю триаду и создаём базу заново.
            try recover()
        }
    }

    private func openHandle(flags: Int32) throws {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)

        guard result == SQLITE_OK, let db else {
            let code = db.map { sqlite3_extended_errcode($0) } ?? result
            let message = db.map { String(cString: sqlite3_errmsg($0)) }
                ?? "код \(result)"
            if let db { sqlite3_close_v2(db) }
            throw HistoryStoreError.openFailed(code: code, message: message)
        }

        // Две копии приложения или внешний читатель не должны ронять запись.
        sqlite3_busy_timeout(db, 2000)
        handle = db
    }

    /// WAL для надёжности и параллельного чтения; таблица — по строке на снимок.
    private func createSchema() throws {
        // PRAGMA journal_mode возвращает строку с итоговым режимом.
        try executeIgnoringRows("PRAGMA journal_mode=WAL;")
        try execute("""
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
            """, bind: { _ in })
    }

    /// Пересоздаёт базу после повреждения.
    private func recover() throws {
        closeHandle()

        // Удаляем журнал вместе с базой: иначе SQLite воспроизведёт
        // старые (в том числе битые) страницы из WAL.
        var urls = [databaseURL]
        for suffix in ["-wal", "-shm"] {
            urls.append(URL(fileURLWithPath: databaseURL.path + suffix))
        }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        try openHandle(flags: flags)
        try createSchema()
    }

    private func closeHandle() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    /// Вставка строки. Проверяет результат привязки и шага.
    private func insert(_ info: BatteryInfo, at date: Date) throws {
        let sql = """
            INSERT OR REPLACE INTO battery_history
            (timestamp, charge_percent, temperature, power_watts,
             adapter_watts, system_power_watts, battery_power_watts, is_charging)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        try execute(sql) { statement in
            let bindings: [Int32] = [
                sqlite3_bind_double(statement, 1, date.timeIntervalSince1970),
                sqlite3_bind_int(statement, 2, Int32(info.currentCharge)),
                info.temperature.map {
                    sqlite3_bind_double(statement, 3, $0)
                } ?? sqlite3_bind_null(statement, 3),
                sqlite3_bind_double(statement, 4, info.powerWatts),
                bindOptional(statement, 5, info.adapterWatts),
                bindOptional(statement, 6, info.systemPowerWatts),
                bindOptional(statement, 7, info.batteryPowerWatts),
                sqlite3_bind_int(statement, 8, info.isCharging ? 1 : 0)
            ]
            if let failed = bindings.first(where: { $0 != SQLITE_OK }) {
                throw HistoryStoreError.writeFailed(
                    code: failed, message: lastError())
            }
        }
    }

    /// Выполняет изменяющий запрос под блокировкой.
    /// Возвращает число изменённых строк.
    @discardableResult
    private func execute(
        _ sql: String,
        bind: (OpaquePointer?) throws -> Void
    ) throws -> Int {
        try withStatement(sql) { statement in
            try bind(statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.writeFailed(
                    code: sqlite3_extended_errcode(handle), message: lastError())
            }
            return Int(sqlite3_changes(handle))
        }
    }

    /// Запрос, который может вернуть строку (PRAGMA): успех — и ROW, и DONE.
    private func executeIgnoringRows(_ sql: String) throws {
        try withStatement(sql) { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                throw HistoryStoreError.writeFailed(
                    code: sqlite3_extended_errcode(handle), message: lastError())
            }
        }
    }

    /// Чтение с восстановлением при повреждении базы.
    private func readWithRecovery<T>(
        _ sql: String,
        bind: (OpaquePointer?) -> Void,
        body: (OpaquePointer?) throws -> T
    ) throws -> T {
        do {
            return try withStatement(sql) { statement in
                bind(statement)
                return try body(statement)
            }
        } catch let error as HistoryStoreError where error.isCorrupt {
            try recover()
            return try withStatement(sql) { statement in
                bind(statement)
                return try body(statement)
            }
        }
    }

    private func withStatement<T>(
        _ sql: String,
        _ body: (OpaquePointer?) throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.writeFailed(
                code: sqlite3_extended_errcode(handle), message: lastError())
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func lastError() -> String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func bindOptional(
        _ statement: OpaquePointer?, _ index: Int32, _ value: Double?
    ) -> Int32 {
        if let value {
            return sqlite3_bind_double(statement, index, value)
        }
        return sqlite3_bind_null(statement, index)
    }

    private func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil : sqlite3_column_double(statement, index)
    }
}

// MARK: - Диагностика (внутреннее, для тестов)

extension HistoryStore {
    /// Ограничивает размер базы страницами — способ воспроизвести
    /// «диск заполнен» (SQLITE_FULL) в тестах.
    func setMaxPageCount(_ pages: Int32) throws {
        try executeIgnoringRows("PRAGMA max_page_count = \(pages);")
    }

    /// Переключает режим журнала. В режиме `DELETE` страницы пишутся сразу
    /// в основной файл, поэтому `max_page_count` действительно упирается
    /// в SQLITE_FULL — в WAL рост уходит в журнал.
    func setJournalModeForTesting(_ mode: String) throws {
        try executeIgnoringRows("PRAGMA journal_mode=\(mode);")
    }

    /// Одна попытка вставки без политики восстановления — чтобы тест
    /// убедился, что ошибка «диск заполнен» действительно возникает.
    func insertOnceForTesting(_ info: BatteryInfo, at date: Date) throws {
        try insert(info, at: date)
    }

    /// Текущее число страниц базы.
    func pageCount() throws -> Int32 {
        try readWithRecovery("PRAGMA page_count;", bind: { _ in }) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw HistoryStoreError.readFailed(
                    code: sqlite3_extended_errcode(handle), message: lastError())
            }
            return sqlite3_column_int(statement, 0)
        }
    }
}
