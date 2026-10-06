import Combine
import Foundation

/// Контроллер зарядки, который сообщает, поддерживается ли управление
/// и чем закончилась последняя запись.
public protocol ReportingChargeController: ChargeController {
    var isSupported: Bool { get }
    var lastError: ChargeControlError? { get }
    /// Почему управление недоступно; nil — доступно.
    var unavailableReason: String? { get }
}

public extension ReportingChargeController {
    var unavailableReason: String? {
        isSupported ? nil
            : ChargeControlError.noSupportedKey.errorDescription
    }
}

extension SMCChargeController: ReportingChargeController {}

/// Что известно о применении политики заряда.
public enum ChargeControlStatus: Equatable, Sendable {
    /// Команд ещё не было — зарядкой управляет система.
    case idle
    /// Управление недоступно: нет helper или поддерживаемого ключа.
    case unsupported
    /// Последняя команда не выполнена; состояние зарядки не подтверждено.
    case failed(String)
    /// Команда подтверждена контроллером.
    case confirmed(allowed: Bool)
}

/// Почему зарядка удерживается.
public enum ChargeHoldReason: Equatable, Sendable {
    case overheat
    case manual
    case limit
}

/// Единая точка решений о зарядке: лимит (FR-001), ручные режимы
/// (FR-002, FR-003) и защита от перегрева (FR-010, FR-011).
///
/// Монитор температуры обращается к менеджеру как к `ChargeController`:
/// перегрев имеет приоритет над любым режимом, а после остывания
/// действует установленный лимит, а не безусловное «заряжать».
///
/// Используется с главного потока.
public final class ChargeManager: ObservableObject, ChargeController,
                                  @unchecked Sendable {
    @Published public private(set) var limit: Int
    @Published public private(set) var mode: ChargeMode = .limit
    @Published public private(set) var status: ChargeControlStatus = .idle
    @Published public private(set) var thermalHold = false

    private let controller: any ReportingChargeController
    private let settings: ChargeSettingsStore
    private var lastCharge: Int?
    /// Последняя отправленная команда. Повтор той же команды не шлётся:
    /// иначе отказ записи повторялся бы каждую секунду.
    private var lastRequested: Bool

    public init(controller: any ReportingChargeController,
                settings: ChargeSettingsStore = ChargeSettingsStore()) {
        self.controller = controller
        self.settings = settings
        self.limit = settings.limit
        self.lastRequested = settings.lastAppliedAllowed
        if !controller.isSupported {
            status = .unsupported
        }
    }

    public var isSupported: Bool { controller.isSupported }

    public var unavailableReason: String? { controller.unavailableReason }

    /// Снять удержание перед сном или выходом из приложения: команда
    /// живёт в SMC сама по себе, и без работающего приложения её некому
    /// отменить — Mac остался бы без зарядки.
    public func releaseHold() {
        guard !lastRequested else { return }
        apply(true)
    }

    /// Причина удержания при текущих настройках; nil — зарядка разрешена.
    public var holdReason: ChargeHoldReason? {
        if thermalHold { return .overheat }
        if mode == .forceDischarge { return .manual }
        guard let charge = lastCharge else { return nil }
        return desiredAllowed(charge: charge) ? nil : .limit
    }

    // MARK: - Действия пользователя

    public func setLimit(_ newLimit: Int) {
        let clamped = ChargeSettings(limit: newLimit).limit
        guard clamped != limit else { return }
        limit = clamped
        settings.limit = clamped
        evaluate()
    }

    public func setMode(_ newMode: ChargeMode) {
        guard newMode != mode else { return }
        mode = newMode
        evaluate()
    }

    /// Повторить последнюю команду после отказа (например, helper
    /// установили уже после запуска приложения).
    public func retry() {
        guard let charge = lastCharge else { return }
        apply(desiredAllowed(charge: charge))
    }

    // MARK: - Данные батареи

    /// Вызывается на каждом снимке батареи.
    public func update(charge: Int) {
        lastCharge = charge
        // FR-003: принудительный заряд сам выключается на 100%.
        if mode == .forceCharge && charge >= 100 {
            mode = .limit
        }
        evaluate()
    }

    // MARK: - ChargeController (защита от перегрева)

    public func setChargingAllowed(_ allowed: Bool) {
        thermalHold = !allowed
        evaluate()
    }

    // MARK: - Внутреннее

    private func desiredAllowed(charge: Int) -> Bool {
        if thermalHold { return false }
        return ChargeLimitPolicy.shouldAllowCharging(
            charge: charge, limit: limit, mode: mode,
            currentlyAllowed: lastRequested)
    }

    private func evaluate() {
        let desired: Bool
        if let charge = lastCharge {
            desired = desiredAllowed(charge: charge)
        } else if thermalHold {
            // Перегрев до первого снимка заряда: удерживаем не дожидаясь.
            desired = false
        } else {
            return
        }
        guard desired != lastRequested else { return }
        apply(desired)
    }

    private func apply(_ allowed: Bool) {
        // Пока управление недоступно, команда не считается отправленной:
        // её нужно выполнить, как только helper появится.
        guard controller.isSupported else {
            status = .unsupported
            return
        }

        lastRequested = allowed

        controller.setChargingAllowed(allowed)

        if let error = controller.lastError {
            // Успех не заявляется: состояние зарядки осталось прежним.
            status = .failed(error.errorDescription ?? String(describing: error))
        } else {
            status = .confirmed(allowed: allowed)
            settings.lastAppliedAllowed = allowed
        }
    }
}
