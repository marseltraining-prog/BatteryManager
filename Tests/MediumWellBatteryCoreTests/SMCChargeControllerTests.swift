import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct SMCChargeControllerTests {
    /// Поддельный SMC: хранит значения ключей и записывает все операции.
    private final class FakeSMC: SMCWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: [UInt8]]
        private var writes: [(key: String, value: [UInt8])] = []
        private let failingKeys: Set<String>

        init(values: [String: [UInt8]] = [:], failingKeys: Set<String> = []) {
            self.values = values
            self.failingKeys = failingKeys
        }

        var recordedWrites: [(key: String, value: [UInt8])] {
            lock.lock(); defer { lock.unlock() }
            return writes
        }

        func read(_ key: String) -> SMCValue? {
            lock.lock(); defer { lock.unlock() }
            guard let value = values[key] else { return nil }
            return SMCValue(key: key, bytes: value, type: "ui8")
        }

        func write(_ key: String, bytes: [UInt8]) throws {
            lock.lock(); defer { lock.unlock() }
            guard values[key] != nil else {
                throw SMCAccessError.keyNotFound(key)
            }
            if failingKeys.contains(key) {
                throw SMCAccessError.writeRejected(key: key, smcResult: 0x86)
            }
            values[key] = bytes
            writes.append((key, bytes))
        }
    }

    // MARK: - Определение ключа

    @Test func detectsTahoeKeyFirst() {
        let smc = FakeSMC(values: ["CHTE": [0, 0, 0, 0], "CH0B": [0], "CH0C": [0]])
        let controller = SMCChargeController(smc: smc)

        #expect(controller.detectedKey?.key == "CHTE")
        #expect(controller.isSupported)
    }

    @Test func fallsBackToLegacyKeyWithCompanion() {
        let smc = FakeSMC(values: ["CH0B": [0], "CH0C": [0]])
        let controller = SMCChargeController(smc: smc)

        let key = try? #require(controller.detectedKey)
        #expect(key?.key == "CH0B")
        #expect(key?.companionKey == "CH0C")
    }

    @Test func detectsChscWhenItIsTheOnlyKey() {
        let smc = FakeSMC(values: ["CHSC": [1]])
        let controller = SMCChargeController(smc: smc)

        #expect(controller.detectedKey?.key == "CHSC")
    }

    @Test func reportsNoSupportWhenNoKeyExists() {
        let controller = SMCChargeController(smc: FakeSMC(values: [:]))

        #expect(controller.isSupported == false)
        #expect(controller.detectedKey == nil)
    }

    // MARK: - Запись

    @Test func holdingWritesHoldValue() {
        let smc = FakeSMC(values: ["CHTE": [0, 0, 0, 0]])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(false)

        #expect(smc.recordedWrites.map(\.key) == ["CHTE"])
        #expect(smc.recordedWrites.first?.value == [0x01, 0x00, 0x00, 0x00])
        #expect(controller.lastError == nil)
    }

    @Test func allowingWritesAllowValue() {
        let smc = FakeSMC(values: ["CHTE": [1, 0, 0, 0]])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(true)

        #expect(smc.recordedWrites.first?.value == [0x00, 0x00, 0x00, 0x00])
    }

    /// На части моделей одного ключа мало: заряд возобновляется во сне,
    /// поэтому пишется и ключ-спутник.
    @Test func legacyKeyWritesCompanionToo() {
        let smc = FakeSMC(values: ["CH0B": [0], "CH0C": [0]])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(false)

        #expect(smc.recordedWrites.map(\.key) == ["CH0B", "CH0C"])
        #expect(smc.recordedWrites.allSatisfy { $0.value == [0x02] })
    }

    @Test func writeRejectionIsReported() {
        let smc = FakeSMC(values: ["CHSC": [1]], failingKeys: ["CHSC"])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(false)

        #expect(controller.lastError != nil)
        #expect(controller.lastError?.errorDescription?.contains("CHSC") == true)
        #expect(smc.recordedWrites.isEmpty)
    }

    /// Регрессия этой машины: CHSC существует, но защищён от записи (SMC 0x86),
    /// CHIE — записываемый. Контроллер обязан перейти к следующему кандидату,
    /// а не сдаться на первом.
    @Test func fallsThroughReadOnlyKeyToWritableOne() {
        let smc = FakeSMC(values: ["CHSC": [0], "CHIE": [0]],
                          failingKeys: ["CHSC"])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(false)

        #expect(smc.recordedWrites.map(\.key) == ["CHIE"])
        // 08 — «адаптер выключен», удержание заряда.
        #expect(smc.recordedWrites.first?.value == [0x08])
        #expect(controller.lastError == nil)
    }

    /// Найденный ключ запоминается: вторая команда не перебирает кандидатов зря.
    @Test func remembersWorkingKeyAfterFirstSuccess() {
        let smc = FakeSMC(values: ["CHSC": [0], "CHIE": [0]],
                          failingKeys: ["CHSC"])
        let controller = SMCChargeController(smc: smc)

        controller.setChargingAllowed(false)
        controller.setChargingAllowed(true)

        #expect(smc.recordedWrites.map(\.key) == ["CHIE", "CHIE"])
        #expect(smc.recordedWrites.last?.value == [0x00])
    }

    @Test func unsupportedModelReportsNoSupportedKey() {
        let controller = SMCChargeController(smc: FakeSMC(values: [:]))

        controller.setChargingAllowed(false)

        #expect(controller.lastError == .noSupportedKey)
    }

    // MARK: - Совместимость с протоколом монитора

    /// Защита от перегрева отключает зарядку через тот же протокол.
    @Test func worksAsChargeControllerForTemperatureMonitor() {
        let smc = FakeSMC(values: ["CHTE": [0, 0, 0, 0]])
        let controller = SMCChargeController(smc: smc)
        let monitor = TemperatureMonitor(controller: controller)

        monitor.evaluate(Self.hot)
        #expect(smc.recordedWrites.first?.value == [0x01, 0x00, 0x00, 0x00])

        monitor.evaluate(Self.cool)
        #expect(smc.recordedWrites.last?.value == [0x00, 0x00, 0x00, 0x00])
    }

    private static let hot = BatteryInfo(
        currentCharge: 80, maxCapacity: 4551, designCapacity: 4629,
        isCharging: true, isPluggedIn: true, voltage: 12.6, amperage: 1.0,
        temperature: 41.0, cycleCount: 85)

    private static let cool = BatteryInfo(
        currentCharge: 80, maxCapacity: 4551, designCapacity: 4629,
        isCharging: true, isPluggedIn: true, voltage: 12.6, amperage: 1.0,
        temperature: 30.0, cycleCount: 85)

    // MARK: - Реальная машина (только чтение)

    /// На этой машине проверяем лишь то, что определённый ключ реально
    /// существует в SMC. Модель без поддерживаемых ключей — допустимый случай.
    @Test func detectedKeyExistsOnRealMachine() throws {
        let controller = SMCChargeController()
        guard let detected = controller.detectedKey else { return }

        #expect(SMCAccess().exists(detected.key))
        #expect(!detected.holdValue.isEmpty)
        #expect(!detected.allowValue.isEmpty)
    }
}
