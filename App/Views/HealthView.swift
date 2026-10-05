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

                row("Проектная ёмкость", "\(data.designCapacity) mAh")
                row("Максимальная ёмкость", "\(data.maxCapacity) mAh")
                row("Здоровье", "\(data.healthPercentage)%")
                row("Количество циклов", "\(data.cycleCount)")
                row("Состояние", conditionText(data.condition))
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
