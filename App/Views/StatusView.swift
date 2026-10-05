import SwiftUI
import MediumWellBatteryCore

/// Вкладка «Статус»: текущий заряд, состояние, температура и мощность.
struct StatusView: View {
    let data: BatteryInfo?

    var body: some View {
        if let data = data {
            VStack(spacing: DesignTokens.spacing3) {
                Text("\(data.currentCharge)%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(data.isCharging
                        ? DesignTokens.charging : DesignTokens.textPrimary)
                    .frame(maxWidth: .infinity)

                Text(statusText(data))
                    .font(.headline)
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: DesignTokens.spacing4) {
                    metric("thermometer.medium", temperatureText(data))
                    metric("bolt", powerText(data))
                }
                .frame(maxWidth: .infinity)

                Divider().opacity(0.15)

                // Распределение мощности по источникам (FR-005),
                // обновляется раз в секунду.
                PowerFlowView(data: data)
            }
            .glassCard()
        } else {
            // Review Focus: настольный Mac — батареи нет.
            Text("Батарея не обнаружена")
                .font(.headline)
                .foregroundColor(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        }
    }

    // MARK: - Элементы

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: DesignTokens.spacing1) {
            Image(systemName: icon)
                .foregroundColor(DesignTokens.textSecondary)
            Text(text)
                .foregroundColor(DesignTokens.textPrimary)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    // MARK: - Тексты

    private func statusText(_ data: BatteryInfo) -> String {
        if data.isCharging {
            return "Зарядка"
        }
        if data.isPluggedIn {
            return "Подключено — заряд остановлен"
        }
        return "Разрядка"
    }

    private func temperatureText(_ data: BatteryInfo) -> String {
        guard let temperature = data.temperature else {
            return "— °C"
        }
        return String(format: "%.1f °C", temperature)
    }

    private func powerText(_ data: BatteryInfo) -> String {
        if let adapterWatts = data.adapterWatts {
            return String(format: "%.0f W адаптер", adapterWatts)
        }
        if let systemPowerWatts = data.systemPowerWatts {
            return String(format: "%.1f W", systemPowerWatts)
        }
        return "—"
    }
}
