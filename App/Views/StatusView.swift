import SwiftUI
import MediumWellBatteryCore

/// Вкладка «Статус»: текущий заряд, состояние, температура и мощность.
struct StatusView: View {
    let data: BatteryInfo?
    let chargeManager: ChargeManager

    var body: some View {
        if let data = data {
            VStack(spacing: DesignTokens.spacing3) {
                statusCard(data)
                ChargeControlView(manager: chargeManager)
            }
        } else {
            // Review Focus: настольный Mac — батареи нет.
            Text("Батарея не обнаружена")
                .font(.headline)
                .foregroundColor(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        }
    }

    private func statusCard(_ data: BatteryInfo) -> some View {
        VStack(spacing: DesignTokens.spacing3) {
            ChargeBar(charge: data.currentCharge,
                      limit: chargeManager.limit,
                      isCharging: data.isCharging,
                      isPluggedIn: data.isPluggedIn)

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

/// Полоса заряда: заполнение — текущий заряд, вертикальная метка — лимит.
private struct ChargeBar: View {
    let charge: Int
    let limit: Int
    let isCharging: Bool
    let isPluggedIn: Bool

    private var color: Color {
        isCharging ? DesignTokens.charging : DesignTokens.discharging
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.55), color.opacity(0.85)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(width * CGFloat(charge) / 100, 44))

                HStack(spacing: DesignTokens.spacing2) {
                    Text("\(charge)%")
                        .font(.title3.monospacedDigit().weight(.bold))
                    if isPluggedIn {
                        Image(systemName: isCharging
                              ? "bolt.fill" : "powerplug.fill")
                            .font(.subheadline)
                    }
                }
                .foregroundColor(DesignTokens.textPrimary)
                .shadow(color: .black.opacity(0.45), radius: 2)
                .padding(.leading, DesignTokens.spacing3)

                if limit < 100 {
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 4, height: geometry.size.height + 8)
                        .offset(x: width * CGFloat(limit) / 100 - 2)
                        .help("Лимит заряда \(limit)%")
                }
            }
            .animation(.easeOut(duration: 0.4), value: charge)
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Заряд \(charge) процентов"
            + (limit < 100 ? ", лимит \(limit) процентов" : ""))
    }
}
