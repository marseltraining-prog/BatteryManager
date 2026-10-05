import SwiftUI

@main
struct BatteryManagerApp: App {
    /// Модель владеет всеми сервисами и запускает их в своём init —
    /// иконка в строке меню обновляется сразу, без открытия окна.
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Подпись иконки в строке меню: процент заряда.
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let data = model.batteryService.currentData {
            Text("\(data.currentCharge)%")
        } else {
            Text("--")
        }
    }
}
