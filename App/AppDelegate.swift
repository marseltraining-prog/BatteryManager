import AppKit
import MediumWellBatteryCore
import SwiftUI

/// Делегат приложения: реакция на клик по иконке в Dock (FR-013).
///
/// Меню-бар и Dock — два входа в одно и то же окно, поэтому делегат
/// открывает панель с тем же содержимым, что и всплывающее окно меню-бара.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?

    /// Клик по иконке в Dock (или повторный запуск) открывает панель.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        NSLog("BatteryManager: переоткрытие приложения (видимые окна: %@)",
              flag ? "да" : "нет")
        showPanel()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("BatteryManager: приложение запущено")
        // Иконке Dock нужен «обычный» режим приложения.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    /// Панель со статусом батареи — открывается по клику на иконку Dock.
    func showPanel() {
        NSLog("BatteryManager: показываю панель")
        if panel == nil {
            let hosting = NSHostingController(
                rootView: MenuBarPopover(model: AppModel.shared))
            let panel = NSPanel(contentViewController: hosting)
            panel.title = "BatteryManager"
            panel.styleMask = [.titled, .closable, .fullSizeContentView]
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
