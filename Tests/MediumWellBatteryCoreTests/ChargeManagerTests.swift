import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct ChargeLimitPolicyTests {
    private func allow(_ charge: Int, limit: Int, mode: ChargeMode = .limit,
                       current: Bool = true) -> Bool {
        ChargeLimitPolicy.shouldAllowCharging(
            charge: charge, limit: limit, mode: mode, currentlyAllowed: current)
    }

    @Test func belowLimitCharges() {
        #expect(allow(50, limit: 80))
    }

    @Test func atOrAboveLimitHolds() {
        #expect(!allow(80, limit: 80))
        #expect(!allow(95, limit: 80))
    }

    /// Внутри гистерезиса решение не меняется — нет дребезга на границе.
    @Test func insideMarginKeepsCurrentDecision() {
        #expect(!allow(79, limit: 80, current: false))
        #expect(allow(79, limit: 80, current: true))
        #expect(allow(78, limit: 80, current: false))
    }

    @Test func limit100DisablesRestriction() {
        #expect(allow(100, limit: 100, current: false))
    }

    @Test func forcedModesIgnoreLimit() {
        #expect(allow(95, limit: 80, mode: .forceCharge, current: false))
        #expect(!allow(30, limit: 80, mode: .forceDischarge, current: true))
    }
}

@Suite
struct ChargeSettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "ChargeSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMeanNoRestriction() {
        let store = ChargeSettingsStore(defaults: makeDefaults())
        #expect(store.limit == 100)
        #expect(store.lastAppliedAllowed)
    }

    @Test func limitIsPersistedAndClamped() {
        let defaults = makeDefaults()
        ChargeSettingsStore(defaults: defaults).limit = 80
        #expect(ChargeSettingsStore(defaults: defaults).limit == 80)

        ChargeSettingsStore(defaults: defaults).limit = 5
        #expect(ChargeSettingsStore(defaults: defaults).limit == 20)
    }

    @Test func keepHoldDuringSleepIsOffByDefaultAndPersisted() {
        let defaults = makeDefaults()
        #expect(!ChargeSettingsStore(defaults: defaults).keepHoldDuringSleep)
        ChargeSettingsStore(defaults: defaults).keepHoldDuringSleep = true
        #expect(ChargeSettingsStore(defaults: defaults).keepHoldDuringSleep)
    }

    @Test func lastAppliedStateIsPersisted() {
        let defaults = makeDefaults()
        ChargeSettingsStore(defaults: defaults).lastAppliedAllowed = false
        #expect(!ChargeSettingsStore(defaults: defaults).lastAppliedAllowed)
    }
}

@Suite
struct ChargeManagerTests {
    private final class FakeController: ReportingChargeController,
                                        @unchecked Sendable {
        var isSupported = true
        var failure: ChargeControlError?
        private(set) var calls: [Bool] = []
        private(set) var lastError: ChargeControlError?

        func setChargingAllowed(_ allowed: Bool) {
            calls.append(allowed)
            lastError = failure
        }
    }

    private func makeStore() -> ChargeSettingsStore {
        let name = "ChargeManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ChargeSettingsStore(defaults: defaults)
    }

    private func makeManager(
        limit: Int = 80, controller: FakeController = FakeController(),
        store: ChargeSettingsStore? = nil
    ) -> (ChargeManager, FakeController, ChargeSettingsStore) {
        let store = store ?? makeStore()
        store.limit = limit
        return (ChargeManager(controller: controller, settings: store),
                controller, store)
    }

    // MARK: - Лимит (FR-001)

    /// Без лимита приложение ничего не пишет в SMC.
    @Test func noLimitMeansNoCommands() {
        let (manager, controller, _) = makeManager(limit: 100)
        manager.update(charge: 100)
        #expect(controller.calls.isEmpty)
        #expect(manager.status == .idle)
    }

    @Test func reachingLimitHoldsChargingOnce() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 79)
        manager.update(charge: 80)
        manager.update(charge: 80)
        #expect(controller.calls == [false])
        #expect(manager.status == .confirmed(allowed: false))
        #expect(manager.holdReason == .limit)
    }

    @Test func chargingResumesBelowMargin() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 80)
        manager.update(charge: 79)
        #expect(controller.calls == [false])
        manager.update(charge: 78)
        #expect(controller.calls == [false, true])
        #expect(manager.holdReason == nil)
    }

    @Test func raisingLimitResumesImmediately() {
        let (manager, controller, store) = makeManager()
        manager.update(charge: 80)
        manager.setLimit(90)
        #expect(controller.calls == [false, true])
        #expect(store.limit == 90)
    }

    @Test func limitIsClamped() {
        let (manager, _, _) = makeManager()
        manager.setLimit(5)
        #expect(manager.limit == 20)
    }

    // MARK: - Ручные режимы (FR-002, FR-003)

    @Test func forceDischargeHoldsUntilCancelled() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 50)
        manager.setMode(.forceDischarge)
        #expect(controller.calls == [false])
        #expect(manager.holdReason == .manual)
        manager.setMode(.limit)
        #expect(controller.calls == [false, true])
    }

    @Test func forceChargeIgnoresLimitAndEndsAtFull() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 85)
        #expect(controller.calls == [false])
        manager.setMode(.forceCharge)
        #expect(controller.calls == [false, true])
        manager.update(charge: 100)
        #expect(manager.mode == .limit)
        #expect(controller.calls == [false, true, false])
    }

    // MARK: - Перегрев (FR-010, FR-011)

    @Test func overheatOverridesForceCharge() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 50)
        manager.setMode(.forceCharge)
        manager.setChargingAllowed(false)
        #expect(controller.calls == [false])
        #expect(manager.holdReason == .overheat)
    }

    /// После остывания действует лимит: выше лимита зарядка не включается.
    @Test func coolingDownRestoresLimitNotBlindCharging() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 90)
        manager.setChargingAllowed(false)
        manager.setChargingAllowed(true)
        #expect(controller.calls == [false])
        #expect(manager.holdReason == .limit)
    }

    @Test func coolingDownResumesChargingBelowLimit() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 50)
        manager.setChargingAllowed(false)
        manager.setChargingAllowed(true)
        #expect(controller.calls == [false, true])
    }

    @Test func overheatBeforeFirstReadingHolds() {
        let (manager, controller, _) = makeManager()
        manager.setChargingAllowed(false)
        #expect(controller.calls == [false])
    }

    // MARK: - Отказы

    /// Отказ записи не выдаётся за успех и не повторяется каждую секунду.
    @Test func failureIsReportedAndNotRetriedBlindly() {
        let controller = FakeController()
        controller.failure = .writeFailed(key: "CHSC", reason: "нет прав")
        let (manager, _, store) = makeManager(controller: controller)
        manager.update(charge: 80)
        manager.update(charge: 81)
        #expect(controller.calls == [false])
        if case .failed = manager.status {} else {
            Issue.record("ожидался статус failed, получен \(manager.status)")
        }
        #expect(store.lastAppliedAllowed)
    }

    @Test func retryRepeatsCommandAfterFailure() {
        let controller = FakeController()
        controller.failure = .writeFailed(key: "CHSC", reason: "нет прав")
        let (manager, _, store) = makeManager(controller: controller)
        manager.update(charge: 80)
        controller.failure = nil
        manager.retry()
        #expect(controller.calls == [false, false])
        #expect(manager.status == .confirmed(allowed: false))
        #expect(!store.lastAppliedAllowed)
    }

    @Test func unsupportedHardwareSendsNothing() {
        let controller = FakeController()
        controller.isSupported = false
        let (manager, _, _) = makeManager(controller: controller)
        manager.update(charge: 90)
        #expect(controller.calls.isEmpty)
        #expect(manager.status == .unsupported)
    }

    /// Helper поставили после запуска — отложенная команда выполняется.
    @Test func commandIsSentOnceControlBecomesAvailable() {
        let controller = FakeController()
        controller.isSupported = false
        let (manager, _, _) = makeManager(controller: controller)
        manager.update(charge: 90)
        controller.isSupported = true
        manager.update(charge: 90)
        #expect(controller.calls == [false])
        #expect(manager.status == .confirmed(allowed: false))
    }

    // MARK: - Сон и выход

    @Test func releaseHoldAllowsChargingAndNextUpdateRestoresLimit() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 85)
        manager.releaseHold()
        #expect(controller.calls == [false, true])
        manager.update(charge: 85)
        #expect(controller.calls == [false, true, false])
    }

    @Test func releaseHoldDoesNothingWhenChargingAllowed() {
        let (manager, controller, _) = makeManager()
        manager.update(charge: 50)
        manager.releaseHold()
        #expect(controller.calls.isEmpty)
    }

    // MARK: - Перезапуск

    /// Удержание пережило выход из приложения — после запуска с выключенным
    /// лимитом его надо снять.
    @Test func staleHoldIsReleasedAfterRestart() {
        let store = makeStore()
        store.lastAppliedAllowed = false
        let (manager, controller, _) = makeManager(limit: 100, store: store)
        manager.update(charge: 60)
        #expect(controller.calls == [true])
        #expect(store.lastAppliedAllowed)
    }
}

@Suite
struct ChargeManagerSystemLimitTests {
    private final class FakeController: ReportingChargeController,
                                        @unchecked Sendable {
        var isSupported = true
        private(set) var calls: [Bool] = []
        private(set) var lastError: ChargeControlError?
        func setChargingAllowed(_ allowed: Bool) { calls.append(allowed) }
    }

    private final class FakeSystemLimit: SystemChargeLimiting,
                                         @unchecked Sendable {
        var isSupported = true
        var availableLimits = [80, 85, 90, 95, 100]
        var current: Int? = 100
        var rejected: Set<Int> = []
        private(set) var writes: [Int] = []

        func currentLimit() -> Int? { current }
        func setLimit(_ percent: Int) throws {
            if rejected.contains(percent) {
                throw SystemChargeLimitError.rejected(limit: percent, reason: "тест")
            }
            writes.append(percent)
            current = percent
        }
    }

    private func make(
        system: FakeSystemLimit = FakeSystemLimit(),
        controller: FakeController = FakeController(),
        savedLimit: Int? = nil
    ) -> (ChargeManager, FakeSystemLimit, FakeController, ChargeSettingsStore) {
        let name = "ChargeManagerSystemLimitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = ChargeSettingsStore(defaults: defaults)
        if let savedLimit { store.limit = savedLimit }
        let manager = ChargeManager(
            controller: controller, systemLimit: system, settings: store)
        return (manager, system, controller, store)
    }

    /// Источник истины — система: при запуске берётся её лимит.
    @Test func adoptsSystemLimitOnStart() {
        let system = FakeSystemLimit()
        system.current = 80
        let (manager, _, controller, store) = make(system: system, savedLimit: 95)
        #expect(manager.usesSystemLimit)
        #expect(manager.limit == 80)
        #expect(store.limit == 80)
        #expect(manager.availableLimits == [80, 85, 90, 95, 100])
        #expect(system.writes.isEmpty)
        #expect(controller.calls.isEmpty)
        #expect(manager.status == .confirmed(allowed: true))
    }

    @Test func settingLimitWritesToSystemOnce() {
        let (manager, system, controller, store) = make()
        manager.setLimit(80)
        manager.update(charge: 90)
        manager.update(charge: 91)
        #expect(system.writes == [80])
        #expect(store.limit == 80)
        // Лимит держит система — helper не трогаем.
        #expect(controller.calls.isEmpty)
        #expect(manager.holdReason == .limit)
    }

    /// Система принимает только свои значения — лимит округляется к ближайшему.
    @Test func limitSnapsToNearestAvailableValue() {
        let (manager, system, _, _) = make()
        manager.setLimit(50)
        #expect(manager.limit == 80)
        manager.setLimit(88)
        #expect(manager.limit == 90)
        #expect(system.writes == [80, 90])
    }

    /// Лимит работает и без helper: права администратора ему не нужны.
    @Test func limitWorksWithoutHelper() {
        let controller = FakeController()
        controller.isSupported = false
        let (manager, system, _, _) = make(controller: controller)
        manager.setLimit(85)
        #expect(manager.isSupported)
        #expect(!manager.canHold)
        #expect(system.writes == [85])
        #expect(manager.status == .confirmed(allowed: true))
    }

    @Test func forceChargeLiftsLimitAndRestoresItAtFull() {
        let system = FakeSystemLimit()
        system.current = 80
        let (manager, _, _, _) = make(system: system)
        manager.update(charge: 80)
        manager.setMode(.forceCharge)
        #expect(system.writes == [100])
        #expect(manager.limit == 80)
        manager.update(charge: 100)
        #expect(manager.mode == .limit)
        #expect(system.writes == [100, 80])
    }

    @Test func forceDischargeUsesHelperAndKeepsSystemLimit() {
        let system = FakeSystemLimit()
        system.current = 80
        let (manager, _, controller, _) = make(system: system)
        manager.update(charge: 90)
        manager.setMode(.forceDischarge)
        #expect(controller.calls == [false])
        #expect(manager.status == .confirmed(allowed: false))
        manager.setMode(.limit)
        #expect(controller.calls == [false, true])
        #expect(system.writes.isEmpty)
    }

    @Test func forceDischargeWithoutHelperIsReportedAsFailure() {
        let controller = FakeController()
        controller.isSupported = false
        let (manager, _, _, _) = make(controller: controller)
        manager.update(charge: 90)
        manager.setMode(.forceDischarge)
        if case .failed = manager.status {} else {
            Issue.record("ожидался failed, получен \(manager.status)")
        }
        manager.setMode(.limit)
        #expect(manager.status == .confirmed(allowed: true))
    }

    @Test func overheatHoldsThroughHelper() {
        let (manager, system, controller, _) = make()
        manager.update(charge: 50)
        manager.setChargingAllowed(false)
        #expect(controller.calls == [false])
        #expect(manager.holdReason == .overheat)
        manager.setChargingAllowed(true)
        #expect(controller.calls == [false, true])
        #expect(system.writes.isEmpty)
    }

    /// Отказ системы не выдаётся за успех и не повторяется каждую секунду.
    @Test func rejectedLimitIsReportedAndNotRetriedBlindly() {
        let system = FakeSystemLimit()
        system.rejected = [85]
        let (manager, _, _, _) = make(system: system)
        manager.setLimit(85)
        manager.update(charge: 50)
        manager.update(charge: 51)
        #expect(system.writes.isEmpty)
        if case .failed = manager.status {} else {
            Issue.record("ожидался failed, получен \(manager.status)")
        }
        system.rejected = []
        manager.retry()
        #expect(system.writes == [85])
        #expect(manager.status == .confirmed(allowed: true))
    }

    /// Лимит поменяли в Настройках macOS — приложение его подхватывает.
    @Test func refreshAdoptsLimitChangedElsewhere() {
        let (manager, system, _, store) = make()
        system.current = 90
        manager.refreshFromSystem()
        #expect(manager.limit == 90)
        #expect(store.limit == 90)
        #expect(system.writes.isEmpty)
    }

    /// Выход во время «Заряда»: лимит возвращается, иначе он остался бы снятым.
    @Test func releaseHoldRestoresLimitAfterForceCharge() {
        let system = FakeSystemLimit()
        system.current = 80
        let (manager, _, _, _) = make(system: system)
        manager.setMode(.forceCharge)
        manager.releaseHold()
        #expect(system.writes == [100, 80])
        #expect(manager.mode == .limit)
    }

    /// Система без лимита (старая macOS) — работает прежняя схема через helper.
    @Test func unsupportedSystemFallsBackToHelperLimit() {
        let system = FakeSystemLimit()
        system.isSupported = false
        let (manager, _, controller, _) = make(system: system, savedLimit: 70)
        #expect(!manager.usesSystemLimit)
        #expect(manager.limit == 70)
        manager.update(charge: 75)
        #expect(controller.calls == [false])
        #expect(system.writes.isEmpty)
    }
}

@Suite
struct HelperChargeControllerTests {
    /// Поддельный helper: скрипт, который пишет аргумент в файл.
    private func makeHelper(exitCode: Int32) throws -> (path: String, log: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("log.txt")
        let script = dir.appendingPathComponent("helper")
        try """
            #!/bin/sh
            echo "$1" >> "\(log.path)"
            echo "вывод helper"
            exit \(exitCode)
            """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script.path, log)
    }

    @Test func missingHelperIsUnsupported() {
        let controller = HelperChargeController(helperPath: "/nonexistent/helper")
        #expect(!controller.isSupported)
        #expect(controller.unavailableReason != nil)
        controller.setChargingAllowed(false)
        #expect(controller.lastError == .helperNotInstalled)
    }

    @Test func sendsHoldAndAllowCommands() throws {
        let helper = try makeHelper(exitCode: 0)
        let controller = HelperChargeController(helperPath: helper.path)
        #expect(controller.isSupported)

        controller.setChargingAllowed(false)
        controller.setChargingAllowed(true)

        let log = try String(contentsOf: helper.log, encoding: .utf8)
        #expect(log == "hold\nallow\n")
        #expect(controller.lastError == nil)
    }

    @Test func helperFailureIsReportedWithOutput() throws {
        let helper = try makeHelper(exitCode: 1)
        let controller = HelperChargeController(helperPath: helper.path)

        controller.setChargingAllowed(false)

        #expect(controller.lastError
                == .writeFailed(key: "helper", reason: "вывод helper"))
    }
}
