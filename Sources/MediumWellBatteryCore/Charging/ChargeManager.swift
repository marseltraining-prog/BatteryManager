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
/// Два канала управления:
/// - **лимит системы** (`SystemChargeLimiting`) — встроенный лимит macOS.
///   Его держит сама система, в том числе во сне и без приложения;
/// - **удержание** (`ReportingChargeController`, helper) — остановка
///   зарядки по команде: перегрев и режим «Разряд». Если лимита системы
///   нет, этим же каналом приложение держит лимит само, с гистерезисом.
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
    /// Значения лимита, которые принимает система; пусто — лимита системы
    /// нет и допустимо любое значение 20...100.
    @Published public private(set) var availableLimits: [Int] = []

    private let controller: any ReportingChargeController
    private let systemLimit: (any SystemChargeLimiting)?
    private let settings: ChargeSettingsStore
    /// Заряд из последнего снимка батареи.
    public private(set) var lastCharge: Int?
    /// Последняя отправленная команда удержания. Повтор той же команды
    /// не шлётся: иначе отказ записи повторялся бы каждую секунду.
    private var lastRequested: Bool
    /// Состояние канала удержания.
    private var holdStatus: ChargeControlStatus = .idle
    /// Лимит, подтверждённый системой.
    private var systemLimitApplied: Int?
    /// Лимит, который система отклонила, — повторно не отправляется.
    private var systemLimitFailed: Int?
    private var limitError: String?

    public init(controller: any ReportingChargeController,
                systemLimit: (any SystemChargeLimiting)? = nil,
                settings: ChargeSettingsStore = ChargeSettingsStore()) {
        self.controller = controller
        self.settings = settings
        self.limit = settings.limit
        self.lastRequested = settings.lastAppliedAllowed

        let limits = systemLimit?.isSupported == true
            ? systemLimit?.availableLimits ?? [] : []
        self.systemLimit = limits.isEmpty ? nil : systemLimit
        self.availableLimits = limits

        if usesSystemLimit {
            // Источник истины — система: лимит могли поменять в Настройках.
            adoptSystemLimit()
        } else if !controller.isSupported {
            holdStatus = .unsupported
        }
        publishStatus()
    }

    /// Лимит держит сама macOS.
    public var usesSystemLimit: Bool { systemLimit != nil }

    /// Можно ли задать лимит.
    public var isSupported: Bool { usesSystemLimit || controller.isSupported }

    /// Можно ли остановить зарядку по команде (перегрев, «Разряд»).
    public var canHold: Bool { controller.isSupported }

    public var unavailableReason: String? {
        usesSystemLimit ? nil : controller.unavailableReason
    }

    public var holdUnavailableReason: String? { controller.unavailableReason }

    /// Перед сном или выходом из приложения: снять удержание и вернуть
    /// лимит. Команда удержания живёт в SMC сама по себе, и без
    /// работающего приложения её некому отменить.
    public func releaseHold() {
        if usesSystemLimit && mode == .forceCharge {
            mode = .limit
            syncSystemLimit()
        }
        if !lastRequested {
            apply(true)
        }
        publishStatus()
    }

    /// Причина удержания при текущих настройках; nil — зарядка разрешена.
    public var holdReason: ChargeHoldReason? {
        if thermalHold { return .overheat }
        if mode == .forceDischarge { return .manual }
        guard let charge = lastCharge else { return nil }
        if usesSystemLimit {
            return mode == .limit && limit < 100 && charge >= limit ? .limit : nil
        }
        return desiredAllowed(charge: charge) ? nil : .limit
    }

    // MARK: - Действия пользователя

    public func setLimit(_ newLimit: Int) {
        let clamped = normalized(newLimit)
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

    /// Повторить команды после отказа (например, helper установили уже
    /// после запуска приложения).
    public func retry() {
        systemLimitFailed = nil
        limitError = nil
        if usesSystemLimit {
            syncSystemLimit()
            apply(desiredHoldChannelAllowed)
        } else if let charge = lastCharge {
            apply(desiredAllowed(charge: charge))
        }
        publishStatus()
    }

    /// Перечитать лимит системы: его могли изменить в Настройках macOS
    /// или в другом приложении.
    public func refreshFromSystem() {
        guard usesSystemLimit, mode != .forceCharge else { return }
        adoptSystemLimit()
        publishStatus()
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

    // MARK: - Лимит системы

    /// Ближайшее допустимое значение лимита.
    private func normalized(_ value: Int) -> Int {
        let clamped = ChargeSettings(limit: value).limit
        guard let nearest = availableLimits.min(by: {
            abs($0 - clamped) < abs($1 - clamped)
        }) else { return clamped }
        return nearest
    }

    private func adoptSystemLimit() {
        guard let current = systemLimit?.currentLimit() else { return }
        systemLimitApplied = current
        guard availableLimits.contains(current), current != limit else { return }
        limit = current
        settings.limit = current
    }

    private func syncSystemLimit() {
        guard let systemLimit else { return }
        // FR-003: «Заряд» — временно снять лимит.
        let target = mode == .forceCharge ? 100 : normalized(limit)
        guard target != systemLimitApplied, target != systemLimitFailed else {
            return
        }

        do {
            try systemLimit.setLimit(target)
            systemLimitApplied = target
            systemLimitFailed = nil
            limitError = nil
        } catch {
            // Успех не заявляется: в системе остался прежний лимит.
            systemLimitFailed = target
            limitError = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }

    // MARK: - Удержание

    /// При лимите системы каналом удержания управляют только перегрев
    /// и режим «Разряд».
    private var desiredHoldChannelAllowed: Bool {
        !(thermalHold || mode == .forceDischarge)
    }

    private func desiredAllowed(charge: Int) -> Bool {
        if thermalHold { return false }
        return ChargeLimitPolicy.shouldAllowCharging(
            charge: charge, limit: limit, mode: mode,
            currentlyAllowed: lastRequested)
    }

    private func evaluate() {
        defer { publishStatus() }

        let desired: Bool
        if usesSystemLimit {
            syncSystemLimit()
            desired = desiredHoldChannelAllowed
        } else if let charge = lastCharge {
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
            holdStatus = .unsupported
            return
        }

        lastRequested = allowed

        controller.setChargingAllowed(allowed)

        if let error = controller.lastError {
            // Успех не заявляется: состояние зарядки осталось прежним.
            holdStatus = .failed(
                error.errorDescription ?? String(describing: error))
        } else {
            holdStatus = .confirmed(allowed: allowed)
            settings.lastAppliedAllowed = allowed
        }
    }

    private func publishStatus() {
        let new: ChargeControlStatus
        if let limitError {
            new = .failed(limitError)
        } else if !usesSystemLimit {
            new = holdStatus
        } else {
            switch holdStatus {
            case .idle:
                // Лимит прочитан из системы или подтверждён ею.
                new = .confirmed(allowed: true)
            case .unsupported:
                // Удержание нужно только при перегреве и «Разряде».
                new = desiredHoldChannelAllowed
                    ? .confirmed(allowed: true)
                    : .failed(controller.unavailableReason
                        ?? "Остановка зарядки недоступна")
            case .failed, .confirmed:
                new = holdStatus
            }
        }
        if new != status { status = new }
    }
}
