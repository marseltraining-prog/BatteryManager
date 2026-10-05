import Combine
import Foundation

/// Управление зарядкой — шов для будущего привилегированного helper (фаза 3).
/// Пока реализаций нет, монитор работает с любым объектом протокола.
public protocol ChargeController: Sendable {
    /// Разрешить (`true`) или запретить (`false`) зарядку батареи.
    func setChargingAllowed(_ allowed: Bool)
}

/// Защита от перегрева (FR-010, FR-011): следит за температурой батареи
/// и на критическом уровне отключает зарядку, а при остывании возвращает её.
///
/// Уровни по спеке: предупреждение 35-40°C, критический — выше 40°C.
/// Уведомление отдаётся наружу через `onStateChange` только при смене
/// состояния — иначе UI получал бы событие каждый опрос.
public final class TemperatureMonitor: ObservableObject {
    /// Текущее состояние температуры.
    @Published public private(set) var state: TemperatureState = .normal

    /// Последнее измеренное значение, °C (nil — сенсора нет).
    @Published public private(set) var temperature: Double?

    /// Вызывается при смене состояния: (новое состояние, температура).
    public var onStateChange: ((TemperatureState, Double?) -> Void)?

    private let reader: any BatteryReading
    private let controller: ChargeController?
    private let warningThreshold: Double
    private let criticalThreshold: Double

    public init(
        reader: any BatteryReading = IOKitBridge(),
        controller: ChargeController? = nil,
        warningThreshold: Double = 35.0,
        criticalThreshold: Double = 40.0
    ) {
        self.reader = reader
        self.controller = controller
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    /// Однократная проверка температуры.
    ///
    /// Review Focus: сбой чтения или отсутствие сенсора не меняют состояние —
    /// мы не сбрасываем защиту и не возобновляем зарядку вслепую.
    public func evaluate() {
        guard let info = reader.getBatteryInfo() else { return }
        evaluate(info)
    }

    /// Проверка по уже полученному снимку — приложение берёт данные из
    /// `BatteryService`, чтобы не читать IOKit дважды за один цикл (NFR-001).
    public func evaluate(_ info: BatteryInfo) {
        temperature = info.temperature

        let newState = info.temperature.map {
            TemperatureState(value: $0,
                             warningThreshold: warningThreshold,
                             criticalThreshold: criticalThreshold)
        } ?? .normal

        let previousState = state
        state = newState

        applyChargePolicy(for: previousState, newState: newState)

        if newState != previousState {
            onStateChange?(newState, info.temperature)
        }
    }

    /// Политика заряда: критический уровень отключает зарядку,
    /// возврат к норме — возобновляет (FR-011).
    private func applyChargePolicy(
        for previousState: TemperatureState,
        newState: TemperatureState
    ) {
        guard let controller else { return }

        // Внимание: `where` в Swift привязывается только к последнему
        // паттерну списка, поэтому ветки разделены явно.
        switch newState {
        case .critical:
            if previousState != .critical {
                controller.setChargingAllowed(false)
            }
        case .normal, .warning:
            if previousState == .critical {
                controller.setChargingAllowed(true)
            }
        }
    }
}
