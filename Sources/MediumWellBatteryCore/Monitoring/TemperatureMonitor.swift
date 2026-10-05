import Combine
import Foundation

/// Управление зарядкой — шов для будущего привилегированного helper (фаза 3).
public protocol ChargeController: Sendable {
    /// Разрешить (`true`) или запретить (`false`) зарядку батареи.
    func setChargingAllowed(_ allowed: Bool)
}

/// Защита от перегрева (FR-010, FR-011): следит за температурой батареи
/// и на критическом уровне отключает зарядку, а после остывания возвращает её.
///
/// Уровни по спеке: предупреждение 35-40°C, критический — выше 40°C.
/// Зарядка возобновляется только при возврате к норме (ниже 35°C) —
/// иначе в диапазоне 35-40°C состояние дребезжало бы каждые 2 секунды.
public final class TemperatureMonitor: ObservableObject {
    /// Текущее состояние температуры.
    @Published public private(set) var state: TemperatureState = .normal

    /// Последнее измеренное значение, °C (nil — сенсора нет).
    @Published public private(set) var temperature: Double?

    /// Вызывается при смене состояния: (прежнее, новое, температура).
    /// Прежнее состояние нужно, чтобы отличить нагрев от возобновления заряда.
    public var onStateChange: ((TemperatureState, TemperatureState, Double?) -> Void)?

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
        // Защита от перепутанных порогов: предупреждение всегда ниже крита.
        self.warningThreshold = min(warningThreshold, criticalThreshold)
        self.criticalThreshold = max(warningThreshold, criticalThreshold)
    }

    /// Однократная проверка температуры.
    ///
    /// Review Focus: сбой чтения или отсутствие сенсора НЕ меняют состояние —
    /// иначе потеря показаний на пике температуры снимала бы защиту и
    /// возобновляла зарядку вслепую.
    public func evaluate() {
        guard let info = reader.getBatteryInfo() else { return }
        evaluate(info)
    }

    /// Проверка по уже полученному снимку — приложение берёт данные из
    /// `BatteryService`, чтобы не читать IOKit дважды за один цикл (NFR-001).
    public func evaluate(_ info: BatteryInfo) {
        guard let value = info.temperature else {
            // Нет данных сенсора: состояние и политика заряда сохраняются.
            return
        }

        temperature = value

        let newState = TemperatureState(
            value: value,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold)

        let previousState = state
        state = newState

        applyChargePolicy(for: previousState, newState: newState)

        if newState != previousState {
            logTransition(from: previousState, to: newState, temperature: value)
            onStateChange?(previousState, newState, value)
        }
    }

    /// Политика заряда (FR-010, FR-011):
    /// критический уровень отключает зарядку, возврат к норме (< 35°C) —
    /// возобновляет. В диапазоне предупреждения зарядка не возобновляется.
    private func applyChargePolicy(
        for previousState: TemperatureState,
        newState: TemperatureState
    ) {
        guard let controller else { return }

        switch newState {
        case .critical:
            if previousState != .critical {
                controller.setChargingAllowed(false)
            }
        case .normal:
            if previousState == .critical {
                controller.setChargingAllowed(true)
            }
        case .warning:
            // Осознанно ничего: 35-40°C — ещё слишком горячо для зарядки.
            break
        }
    }

    /// События перегрева пишутся в системный журнал (FR-010, NFR-004).
    private func logTransition(
        from previous: TemperatureState,
        to new: TemperatureState,
        temperature: Double
    ) {
        NSLog("BatteryManager: температура %.1f°C, состояние %@ → %@",
              temperature, String(describing: previous), String(describing: new))
    }
}
