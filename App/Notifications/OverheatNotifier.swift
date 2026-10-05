import Foundation
import MediumWellBatteryCore
import UserNotifications

/// Системные уведомления о перегреве батареи (FR-010).
///
/// Доставка уведомлений требует, чтобы приложение было правильно подписано;
/// при отказе разрешения защита всё равно работает — предупреждение видно
/// в интерфейсе (янтарная/красная иконка Dock).
final class OverheatNotifier {
    /// Запрашивает разрешение на уведомления (однократно, при запуске).
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Отправляет уведомление о нагреве. Для нормального состояния — молчит.
    func notify(state: TemperatureState, temperature: Double?) {
        guard state != .normal else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        let value = temperature.map { String(format: "%.1f°C", $0) } ?? "—"

        switch state {
        case .critical:
            content.title = "Критический перегрев батареи"
            content.body = "Температура \(value) — зарядка остановлена до остывания."
        case .warning:
            content.title = "Батарея нагревается"
            content.body = "Температура \(value). Рекомендуется снизить нагрузку."
        case .normal:
            return
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
