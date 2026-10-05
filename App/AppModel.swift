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
    @Published private(set) var chartData = ChartData(
        charge: [], temperature: [], power: [])
    @Published var selectedTab: PopoverTab = .status

    let batteryService = BatteryService()
    let temperatureMonitor = TemperatureMonitor()

    let historyStore: HistoryStore?
    private let historyRecorder: HistoryRecorder?
    private let notifier = OverheatNotifier()
    private var dockIconManager: DockIconManager?
    private var cancellables: Set<AnyCancellable> = []
    private var chartTimer: DispatchSourceTimer?
    private var started = false

    init() {
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
                self?.temperatureMonitor.evaluate(info)
            }
            .store(in: &cancellables)

        temperatureMonitor.onStateChange = { [weak self] state, temperature in
            self?.notifier.notify(state: state, temperature: temperature)
        }

        startChartRefresh()
    }

    /// Перечитывает историю за 24 часа и обновляет точки графиков.
    func reloadCharts() {
        guard let historyStore else { return }
        let since = Date().addingTimeInterval(-24 * 3600)
        let records = (try? historyStore.records(since: since)) ?? []
        chartData = ChartData.points(from: records)
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
