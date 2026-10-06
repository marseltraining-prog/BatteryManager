import MediumWellBatteryCore
import ServiceManagement
import SwiftUI

/// Вкладка «Настройки»: автозапуск, поведение во сне, состояние helper.
struct SettingsView: View {
    let settings: ChargeSettingsStore
    @ObservedObject var chargeManager: ChargeManager

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var keepHoldDuringSleep = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) })
            ) {
                title("Запускать при входе в систему",
                      "Лимит заряда действует, только пока приложение запущено.")
            }

            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(DesignTokens.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.15)

            Toggle(isOn: Binding(
                get: { keepHoldDuringSleep },
                set: {
                    keepHoldDuringSleep = $0
                    settings.keepHoldDuringSleep = $0
                })
            ) {
                title("Сохранять удержание заряда во сне",
                      "Заряд не поднимется выше лимита, пока Mac спит. "
                      + "Но во сне приложение не может вернуть зарядку: "
                      + "за долгий сон батарея может сильно разрядиться.")
            }

            Divider().opacity(0.15)

            HStack(alignment: .firstTextBaseline) {
                Text("Helper управления зарядом")
                    .foregroundColor(DesignTokens.textSecondary)
                Spacer()
                Text(chargeManager.isSupported ? "установлен" : "не установлен")
                    .foregroundColor(chargeManager.isSupported
                        ? DesignTokens.charging : DesignTokens.warning)
            }
            .font(.subheadline)

            HStack {
                Text("Версия")
                    .foregroundColor(DesignTokens.textSecondary)
                Spacer()
                Text(Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "—")
                    .foregroundColor(DesignTokens.textPrimary)
                    .monospacedDigit()
            }
            .font(.subheadline)
        }
        .toggleStyle(.switch)
        .tint(DesignTokens.charging)
        .glassCard()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            keepHoldDuringSleep = settings.keepHoldDuringSleep
        }
    }

    private func title(_ text: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(DesignTokens.textPrimary)
            Text(caption)
                .font(.caption2)
                .foregroundColor(DesignTokens.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Автозапуск через SMAppService. Переключатель показывает то, что
    /// подтвердила система, а не то, что нажал пользователь.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Не удалось изменить автозапуск: "
                + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
