import Testing
@testable import MediumWellBatteryCore

/// Интеграционные тесты на реальном железе: чтение SMC доступно
/// обычному пользователю, запись требует root и здесь не проверяется.
@Suite(.serialized)
struct SMCAccessTests {
    private let smc = SMCAccess()

    @Test func readsChargeControlKey() throws {
        let value = try #require(smc.read("CHSC"),
                                 "на этом Mac ожидается ключ управления зарядом CHSC")

        #expect(value.bytes.count == 1)
        // 00 — заряд удерживается, 01 — заряд разрешён.
        #expect(value.bytes[0] == 0 || value.bytes[0] == 1)
    }

    @Test func readsAdapterLedColorKey() throws {
        let value = try #require(smc.read("ACLC"))
        #expect(value.bytes.count == 1)
    }

    @Test func readsBatteryTemperatureKey() throws {
        let value = try #require(smc.read("TB0T"))
        #expect(value.type == "flt")
        #expect(value.bytes.count == 4)
    }

    @Test func unknownKeyReturnsNil() {
        #expect(smc.read("ZZZZ") == nil)
        #expect(smc.exists("ZZZZ") == false)
    }

    @Test func existsFindsKnownKey() {
        #expect(smc.exists("CHSC"))
    }

    /// Запись в несуществующий ключ отклоняется понятной ошибкой.
    @Test func writingUnknownKeyReportsKeyNotFound() {
        #expect(throws: SMCAccessError.keyNotFound("ZZZZ")) {
            try smc.write("ZZZZ", bytes: [0])
        }
    }

    /// Код типа разбирается в строку.
    @Test func decodesTypeCode() throws {
        let value = try #require(smc.read("CHSC"))
        #expect(value.type == "ui8")
        #expect(value.integer <= 1)
    }
}
