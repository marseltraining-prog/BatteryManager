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

                // Распределение мощности (FR-005): сколько идёт в батарею,
                // сколько потребляет система.
                VStack(spacing: DesignTokens.spacing2) {
                    powerRow(label: "В батарею",
                             value: data.batteryPowerWatts,
                             color: DesignTokens.charging)
                    powerRow(label: "Система",
                             value: data.systemPowerWatts,
                             color: DesignTokens.discharging)
                }
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

    private func powerRow(label: String, value: Double?, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
            Text(value.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundColor(color)
        }
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
