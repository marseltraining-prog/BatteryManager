import Foundation

/// Периодически записывает снимки батареи в `HistoryStore` и чистит
/// старые записи (по умолчанию: раз в 60 секунд, хранение 24 часа).
///
/// Review Focus: если источник не отдал данных (нет батареи / сбой IOKit),
/// запись пропускается — в базе не появляются пустые строки.
public final class HistoryRecorder {
    private let reader: any BatteryReading
    private let store: HistoryStore
    private let interval: TimeInterval
    private let retention: TimeInterval
    private let queue = DispatchQueue(
        label: "com.mediumwell.battery.recorder", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// - Parameters:
    ///   - reader: источник данных (по умолчанию — реальный `IOKitBridge`).
    ///   - store: хранилище истории.
    ///   - interval: период записи, секунды (по умолчанию 60 — по спеке).
    ///   - retention: срок хранения записей, секунды (по умолчанию 24 часа).
    public init(
        reader: any BatteryReading = IOKitBridge(),
        store: HistoryStore,
        interval: TimeInterval = 60.0,
        retention: TimeInterval = 24 * 3600
    ) {
        self.reader = reader
        self.store = store
        self.interval = interval
        self.retention = retention
    }

    deinit {
        timer?.cancel()
    }

    /// Запускает периодическую запись. Первая запись — сразу.
    public func start() {
        guard timer == nil else { return }

        recordInBackground()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.recordInBackground()
        }
        timer.resume()
        self.timer = timer
    }

    /// Останавливает запись. Повторный вызов безопасен.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Однократная запись снимка. Бросает ошибку хранилища вызывающему;
    /// отсутствие данных от источника ошибкой не считается.
    public func recordNow(at date: Date = Date()) throws {
        guard let info = reader.getBatteryInfo() else { return }
        try store.record(info, at: date)
    }

    /// Удаляет записи старше срока хранения.
    public func prune(from date: Date = Date()) throws {
        try store.prune(olderThan: retention, from: date)
    }

    private func recordInBackground() {
        do {
            try recordNow()
            try prune()
        } catch {
            // Review Focus: ошибка БД (например, диск заполнен) не должна
            // ронять фоновый опрос — следующий тик попробует снова.
            NSLog("BatteryManager: запись истории не удалась: %@",
                  error.localizedDescription)
        }
    }
}
