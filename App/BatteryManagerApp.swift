import SwiftUI

@main
struct BatteryManagerApp: App {
    /// Делегат нужен для открытия панели по клику на иконку в Dock (FR-013).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Модель владеет всеми сервисами и запускает их в своём init —
    /// иконка в строке меню обновляется сразу, без открытия окна.
    /// Экземпляр общий с делегатом (панель Dock показывает те же данные).
    @StateObject private var model = AppModel.shared

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
