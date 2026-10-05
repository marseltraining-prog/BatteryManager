import Foundation
import MediumWellBatteryCore
import UserNotifications

/// Системные уведомления о перегреве батареи (FR-010, FR-011).
///
/// Доставка уведомлений требует правильно подписанного приложения;
/// при отказе разрешения защита всё равно работает — состояние видно
/// в интерфейсе (янтарная/красная иконка Dock и строка меню).
final class OverheatNotifier {
    /// Запрашивает разрешение на уведомления (однократно, при запуске).
    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Уведомление о смене состояния. Молчит, пока всё в норме.
    func notify(
        previous: TemperatureState,
        current: TemperatureState,
        temperature: Double?
    ) {
        guard let (title, body) = message(
            previous: previous, current: current, temperature: temperature) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Текст уведомления. Возобновление заряда тоже озвучивается (FR-011).
    private func message(
        previous: TemperatureState,
        current: TemperatureState,
        temperature: Double?
    ) -> (String, String)? {
        let value = temperature.map { String(format: "%.1f°C", $0) } ?? "—"

        switch (previous, current) {
        case (_, .critical):
            return ("Критический перегрев батареи",
                    "Температура \(value) — зарядка остановлена до остывания.")
        case (.normal, .warning):
            return ("Батарея нагревается",
                    "Температура \(value). Рекомендуется снизить нагрузку.")
        case (.critical, .normal), (.critical, .warning):
            return ("Зарядка возобновлена",
                    "Батарея остыла до \(value).")
        default:
            return nil
        }
    }
}
