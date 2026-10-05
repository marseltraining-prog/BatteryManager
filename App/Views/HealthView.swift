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
                    Spacer()
                    Text("\(data.healthPercentage)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(healthColor(data.healthPercentage))
                }

                Divider().opacity(0.2)

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
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func healthColor(_ percentage: Int) -> Color {
        switch percentage {
        case 80...: return DesignTokens.charging
        case 60..<80: return DesignTokens.warning
        default: return DesignTokens.critical
        }
    }

    private func conditionText(_ condition: BatteryCondition) -> String {
        switch condition {
        case .normal: return "Норма"
        case .replaceSoon: return "Скоро замена"
        case .serviceBattery: return "Требует обслуживания"
        }
    }
}
