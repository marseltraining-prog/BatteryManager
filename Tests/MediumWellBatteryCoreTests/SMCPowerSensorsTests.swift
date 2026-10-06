import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct SMCPowerSensorsTests {
    private struct FakeSMC: SMCWriting {
        let values: [String: SMCValue]
        func read(_ key: String) -> SMCValue? { values[key] }
        func write(_ key: String, bytes: [UInt8]) throws {}
    }

    private func float(_ key: String, _ value: Float) -> SMCValue {
        let bits = value.bitPattern
        return SMCValue(key: key, bytes: (0..<4).map { UInt8((bits >> (8 * $0)) & 0xFF) },
                        type: "flt")
    }

    private func milliwatts(_ value: Int32) -> SMCValue {
        let bits = UInt32(bitPattern: value)
        return SMCValue(key: "B0AP", bytes: (0..<4).map { UInt8((bits >> (8 * $0)) & 0xFF) },
                        type: "si32")
    }

    private func sensors(adapter: Float, system: Float, battery: Int32) -> SMCPowerSensors {
        SMCPowerSensors(smc: FakeSMC(values: [
            "PDTR": float("PDTR", adapter), "PSTR": float("PSTR", system),
            "B0AP": milliwatts(battery)
        ]))
    }

    /// Значения с реальной машины во время зарядки: 67 3f 00 00 = 16231 мВт.
    @Test func decodesRealChargingSample() {
        let value = SMCValue(key: "B0AP", bytes: [0x67, 0x3f, 0x00, 0x00], type: "si32")
        #expect(value.signedInteger == 16231)
        let reading = sensors(adapter: 28.2, system: 11.39, battery: 16231).read()
        #expect(reading?.battery == 16.231)
        #expect(abs((reading?.adapterInput ?? 0) - 28.2) < 0.001)
        #expect(abs((reading?.system ?? 0) - 11.39) < 0.001)
    }

    @Test func decodesNegativeBatteryPower() {
        #expect(sensors(adapter: 0, system: 9, battery: -9300).read()?.battery == -9.3)
    }

    /// Без питания от адаптера батарея отдаёт — при любом знаке датчика.
    @Test func withoutAdapterBatteryPowerIsAlwaysNegative() {
        #expect(sensors(adapter: 0.01, system: 9, battery: 9300).read()?.battery == -9.3)
    }

    @Test func decodesSignedSixteenBitValue() {
        let value = SMCValue(key: "B0AC", bytes: [0xb5, 0xfd], type: "si16")
        #expect(value.signedInteger == -587)
    }

    @Test func missingKeyGivesNil() {
        let smc = FakeSMC(values: ["PDTR": float("PDTR", 28)])
        #expect(SMCPowerSensors(smc: smc).read() == nil)
    }

    @Test func implausibleValuesGiveNil() {
        #expect(sensors(adapter: 5000, system: 10, battery: 0).read() == nil)
        #expect(sensors(adapter: .nan, system: 10, battery: 0).read() == nil)
    }

    @Test func wrongTypeIsNotDecodedAsFloat() {
        let value = SMCValue(key: "PDTR", bytes: [0, 0, 0, 0], type: "ui32")
        #expect(value.floatValue == nil)
    }
}
