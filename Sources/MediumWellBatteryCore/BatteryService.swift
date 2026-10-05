import Combine
import Foundation

/// Источник данных батареи. Абстракция над `IOKitBridge` для подмены в тестах.
public protocol BatteryReading: Sendable {
    /// Снимок данных батареи прямо сейчас; nil — батарея не найдена / сбой чтения.
    func getBatteryInfo() -> BatteryInfo?
}

extension IOKitBridge: BatteryReading {}

/// Сервис мониторинга батареи: периодически опрашивает источник
/// и публикует последние валидные данные для UI (Combine/@Published).
///
/// При сбое чтения предыдущие данные сохраняются (fallback по Review Focus):
/// однократная ошибка IOKit не сбрасывает состояние интерфейса.
public final class BatteryService: ObservableObject {
    /// Последний валидный снимок данных батареи.
    @Published public private(set) var currentData: BatteryInfo?
    /// Идёт ли периодический опрос прямо сейчас.
    @Published public private(set) var isMonitoring = false

    private let bridge: any BatteryReading
    private let updateInterval: TimeInterval
    private let monitorQueue = DispatchQueue(
        label: "com.mediumwell.battery.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// - Parameters:
    ///   - bridge: источник данных (по умолчанию — реальный `IOKitBridge`).
    ///   - updateInterval: период опроса в секундах (по умолчанию 2.0 — по спеке).
    public init(bridge: any BatteryReading = IOKitBridge(),
                updateInterval: TimeInterval = 2.0) {
        self.bridge = bridge
        self.updateInterval = updateInterval
    }

    deinit {
        timer?.cancel()
    }

    /// Запускает периодический опрос. Первый опрос выполняется сразу.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + updateInterval,
                       repeating: updateInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                self.refresh()
            } else {
                DispatchQueue.main.async { self.refresh() }
            }
        }
        timer.resume()
        self.timer = timer
    }

    /// Останавливает периодический опрос.
    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
        isMonitoring = false
    }

    /// Однократное чтение и публикация данных. Если источник не ответил —
    /// опубликованные данные не трогаем (последний валидный снимок остаётся).
    public func refresh() {
        guard let info = bridge.getBatteryInfo() else { return }
        currentData = info
    }
}
