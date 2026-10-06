import MediumWellBatteryCore
import SwiftUI

/// Вкладка «Здоровье»: ёмкости, здоровье, циклы и состояние батареи (FR-006).
struct HealthView: View {
    let data: BatteryInfo?

    var body: some View {
        if let data {
            VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                HStack(spacing: DesignTokens.spacing2) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(DesignTokens.charging)
                    Text("Здоровье батареи")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignTokens.textPrimary)
                    Spacer()
                    Text("\(data.healthPercentage)%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(healthColor(data.healthPercentage))
                }

                Divider().opacity(0.15)

                row("Проектная ёмкость", capacityText(data, data.designCapacity))
                row("Максимальная ёмкость", capacityText(data, data.maxCapacity))
                // Оценка macOS: по ней система считает «Максимальную
                // ёмкость» в Настройках, поэтому цифры могут расходиться.
                row("Ёмкость macOS", capacityText(data, data.nominalCapacity))
                row("Количество циклов", "\(data.cycleCount)")
                row("Состояние", conditionText(data.condition))

                if let advice = advice(data.condition) {
                    Divider().opacity(0.15)
                    Label(advice, systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(healthColor(data.healthPercentage))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard()
        } else {
            Text("Батарея не обнаружена")
                .font(.headline)
                .foregroundColor(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(DesignTokens.textPrimary)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    /// «4486 mAh  97%»; «—», если система не отдала значение.
    private func capacityText(_ data: BatteryInfo, _ capacity: Int?) -> String {
        guard let capacity, capacity > 0 else { return "—" }
        guard let percent = data.percentOfDesign(capacity) else {
            return "\(capacity) mAh"
        }
        return "\(capacity) mAh  \(percent)%"
    }

    /// Рекомендация по обслуживанию (FR-016); nil — батарея в норме.
    private func advice(_ condition: BatteryCondition) -> String? {
        switch condition {
        case .replaceSoon:
            return "Ёмкость заметно снизилась. Батарея работает, но стоит "
                + "запланировать замену."
        case .serviceBattery:
            return "Ёмкость ниже 60% от проектной. Рекомендуется замена "
                + "батареи в сервисе."
        case .normal, .unknown:
            return nil
        }
    }

    private func healthColor(_ percentage: Int) -> Color {
        switch percentage {
        case 80...: return DesignTokens.charging
        case 60..<80: return DesignTokens.warning
        case 1..<60: return DesignTokens.critical
        default: return DesignTokens.textTertiary // нет данных
        }
    }

    private func conditionText(_ condition: BatteryCondition) -> String {
        switch condition {
        case .normal: return "Норма"
        case .replaceSoon: return "Скоро замена"
        case .serviceBattery: return "Требует обслуживания"
        case .unknown: return "—"
        }
    }
}
