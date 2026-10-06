import Foundation
import Testing
@testable import MediumWellBatteryCore

@Suite
struct PowerFlowTests {
    private func info(plugged: Bool, charging: Bool, battery: Double?,
                      system: Double?) -> BatteryInfo {
        BatteryInfo(
            currentCharge: 65, maxCapacity: 4500, designCapacity: 4629,
            isCharging: charging, isPluggedIn: plugged, voltage: 12, amperage: 1,
            temperature: 30, cycleCount: 85, adapterWatts: plugged ? 50 : nil,
            systemPowerWatts: system, batteryPowerWatts: battery)
    }

    @Test func chargingSplitsAdapterPowerBetweenBatteryAndSystem() {
        let flow = PowerFlow(info(plugged: true, charging: true,
                                  battery: 30.6, system: 19.68))
        #expect(flow.source == .adapter)
        #expect(flow.toBattery == 30.6)
        #expect(flow.toSystem == 19.68)
        #expect(abs(flow.batteryShare - 0.6086) < 0.001)
    }

    /// На лимите: адаптер питает только систему.
    @Test func heldAtLimitSendsEverythingToSystem() {
        let flow = PowerFlow(info(plugged: true, charging: false,
                                  battery: 0, system: 12))
        #expect(flow.source == .adapter)
        #expect(flow.toBattery == 0)
        #expect(flow.batteryShare == 0)
    }

    /// Заряд выше лимита или «Разряд»: адаптер подключён, но питает батарея.
    @Test func pluggedButDrainingUsesBatteryAsSource() {
        let flow = PowerFlow(info(plugged: true, charging: false,
                                  battery: -9.3, system: 9.7))
        #expect(flow.source == .battery)
        #expect(flow.toBattery == 0)
        #expect(flow.toSystem == 9.7)
    }

    @Test func onBatteryWithoutSystemTelemetryUsesBatteryOutput() {
        let flow = PowerFlow(info(plugged: false, charging: false,
                                  battery: -8.4, system: nil))
        #expect(flow.source == .battery)
        #expect(flow.toSystem == 8.4)
    }

    /// Шум около нуля не переключает источник на батарею.
    @Test func noiseAroundZeroKeepsAdapterAsSource() {
        let flow = PowerFlow(info(plugged: true, charging: false,
                                  battery: -0.2, system: 10))
        #expect(flow.source == .adapter)
    }

    @Test func noDataGivesEmptyFlow() {
        let flow = PowerFlow(info(plugged: true, charging: false,
                                  battery: nil, system: nil))
        #expect(flow.total == 0)
        #expect(flow.batteryShare == 0)
    }
}
