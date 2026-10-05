import SwiftUI
import MediumWellBatteryCore

/// Вкладка «Статус»: текущий заряд, состояние, температура и мощность.
struct StatusView: View {
    let data: BatteryInfo?

    var body: some View {
        if let data = data {
            VStack(spacing: DesignTokens.spacing3) {
                Text("\(data.currentCharge)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(data.isCharging
                        ? DesignTokens.charging : .white)
                    .frame(maxWidth: .infinity)

                Text(statusText(data))
                    .font(.headline)
                    .foregroundColor(.secondary)

                HStack(spacing: DesignTokens.spacing4) {
                    Label(temperatureText(data), systemImage: "thermometer.medium")
                    Label(powerText(data), systemImage: "bolt")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
            }
            .glassCard()
        } else {
            // Review Focus: настольный Mac — батареи нет.
            Text("Батарея не обнаружена")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .glassCard()
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
            return "—°C"
        }
        return String(format: "%.1f°C", temperature)
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
