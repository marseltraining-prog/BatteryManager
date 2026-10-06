import AppKit
import Combine
import Foundation
import MediumWellBatteryCore

/// Вкладки главного окна.
enum PopoverTab: String, CaseIterable, Identifiable {
    case status = "Статус"
    case charts = "Графики"
    case health = "Здоровье"

    var id: String { rawValue }
}

/// Владелец сервисов приложения: мониторинг, история, защита от перегрева
/// и иконка Dock. Собирает всё в одном месте, чтобы представления
/// оставались простыми.
@MainActor
final class AppModel: ObservableObject {
    /// Общий экземпляр: к нему обращаются и сцены SwiftUI, и делегат
    /// приложения (панель по клику на иконку Dock).
    static let shared = AppModel()

    @Published private(set) var chartData = ChartData(
        charge: [], temperature: [], power: [])
    @Published private(set) var historyUnavailable = false
    @Published var selectedTab: PopoverTab = .status

    let batteryService = BatteryService()
    /// Лимит заряда, ручные режимы и удержание при перегреве.
    let chargeManager: ChargeManager
    let temperatureMonitor: TemperatureMonitor

    let historyStore: HistoryStore?
    private let historyRecorder: HistoryRecorder?
    private let notifier = OverheatNotifier()
    private var dockIconManager: DockIconManager?
    private var cancellables: Set<AnyCancellable> = []
    private let chartQueue = DispatchQueue(
        label: "com.mediumwell.battery.charts", qos: .utility)
    private var chartTimer: DispatchSourceTimer?
    private var started = false
    /// Счётчик засыпаний: отменяет отложенный запуск после пробуждения.
    private var wakeGeneration = 0

    init() {
        // Перегрев отключает зарядку через менеджер: после остывания
        // действует лимит пользователя, а не безусловное «заряжать».
        let chargeManager = ChargeManager(controller: HelperChargeController())
        self.chargeManager = chargeManager
        temperatureMonitor = TemperatureMonitor(controller: chargeManager)

        let store = try? HistoryStore(
            databaseURL: HistoryStore.defaultDatabaseURL())
        historyStore = store
        historyRecorder = store.map { HistoryRecorder(store: $0) }

        // Сервисы стартуют сразу: иконка в строке меню и плитка Dock
        // должны показывать данные, даже если окно ни разу не открывали.
        start()
    }

    /// Запускает все сервисы приложения. Повторный вызов безопасен.
    func start() {
        guard !started else { return }
        started = true

        notifier.requestAuthorization()
        batteryService.startMonitoring()
        historyRecorder?.start()

        // Иконка Dock: процент заряда и цвет по состоянию (FR-012).
        dockIconManager = DockIconManager(
            batteryService: batteryService,
            temperatureMonitor: temperatureMonitor)

        // Температура оценивается по тому же снимку, что и UI, —
        // без второго чтения IOKit за цикл (NFR-001).
        batteryService.$currentData
            .compactMap { $0 }
            .sink { [weak self] info in
                self?.chargeManager.update(charge: info.currentCharge)
                self?.temperatureMonitor.evaluate(info)
            }
            .store(in: &cancellables)

        // Представления наблюдают модель, а данные живут во вложенных
        // сервисах — их изменения пробрасываются наружу.
        batteryService.objectWillChange
            .merge(with: chargeManager.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Уведомления о нагреве и о возобновлении заряда (FR-010, FR-011).
        temperatureMonitor.onStateChange = { [weak self] previous, current, value in
            self?.notifier.notify(previous: previous, current: current,
                                  temperature: value)
        }

        observeSleep()
        startChartRefresh()
    }

    /// Сон (NFR-006): мониторинг и запись истории приостанавливаются,
    /// а удержание заряда снимается — во сне приложение не работает
    /// и не смогло бы вернуть зарядку. После пробуждения всё
    /// возобновляется через 5 секунд, когда данные батареи устоятся.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                NSLog("BatteryManager: сон — мониторинг приостановлен")
                self.wakeGeneration += 1
                self.chargeManager.releaseHold()
                self.batteryService.stopMonitoring()
                self.historyRecorder?.stop()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let generation = self.wakeGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    // Mac успел снова уснуть — этот запуск уже не нужен.
                    guard let self, self.wakeGeneration == generation else { return }
                    NSLog("BatteryManager: пробуждение — мониторинг возобновлён")
                    self.batteryService.startMonitoring()
                    self.historyRecorder?.start()
                }
            }
            .store(in: &cancellables)
    }

    /// Перечитывает историю за 24 часа и обновляет точки графиков.
    /// Чтение идёт вне главного потока: в базе может быть до 1440 записей
    /// (NFR-001), а публикация результата — на главном потоке.
    func reloadCharts() {
        guard let historyStore else { return }
        let since = Date().addingTimeInterval(-24 * 3600)

        chartQueue.async { [weak self] in
            var points: ChartData?
            var failed = false

            do {
                let records = try historyStore.records(since: since)
                points = ChartData.points(from: records)
            } catch {
                failed = true
                NSLog("BatteryManager: не удалось прочитать историю: %@",
                      String(describing: error))
            }

            Task { @MainActor in
                guard let self else { return }
                self.historyUnavailable = failed
                if let points {
                    self.chartData = points
                }
            }
        }
    }

    deinit {
        chartTimer?.cancel()
    }

    /// Графики обновляются реже интерфейса: запись истории идёт раз в минуту
    /// (NFR-002 — минимальная нагрузка на батарею).
    private func startChartRefresh() {
        reloadCharts()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.reloadCharts()
        }
        timer.resume()
        chartTimer = timer
    }
}
