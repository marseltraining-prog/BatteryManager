import SwiftUI
import MediumWellBatteryCore

@main
struct BatteryManagerApp: App {
    @StateObject private var batteryService = BatteryManagerApp.makeService()

    /// Фабрика сервиса: опрос батареи стартует вместе с приложением,
    /// чтобы иконка в строке меню обновлялась даже при закрытом окне.
    private static func makeService() -> BatteryService {
        let service = BatteryService()
        service.startMonitoring()
        return service
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(batteryService: batteryService)
        } label: {
            if let data = batteryService.currentData {
                Text("\(data.currentCharge)%")
            } else {
                Text("--")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
