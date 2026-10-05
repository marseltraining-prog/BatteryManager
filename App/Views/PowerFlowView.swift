import MediumWellBatteryCore
import SwiftUI

/// Визуализация потребления из разных источников (FR-005):
/// слева — мощность адаптера, справа — полосы «в батарею» и «система».
///
/// Полосы пропорциональны измеренным значениям, поэтому по ним видно,
/// куда уходит энергия прямо сейчас.
struct PowerFlowView: View {
    let data: BatteryInfo?

    /// Полная шкала: мощность адаптера, а если её нет — сумма потребителей.
    private var scale: Double {
        guard let data else { return 0 }
        let consumers = battery + system
        return max(data.adapterWatts ?? 0, consumers, 1)
    }

    private var battery: Double {
        max(data?.batteryPowerWatts ?? 0, 0)
    }

    /// Потребление системы; при разрядке берём модуль мощности батареи.
    private var system: Double {
        guard let data else { return 0 }
        if let systemWatts = data.systemPowerWatts, systemWatts > 0 {
            return systemWatts
        }
        return abs(min(data.batteryPowerWatts ?? 0, 0))
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.spacing3) {
            adapterBlock
            VStack(spacing: DesignTokens.spacing2) {
                bar(
                    label: "В батарею",
                    value: battery,
                    color: DesignTokens.charging,
                    icon: "battery.100.bolt")
                bar(
                    label: "Система",
                    value: system,
                    color: DesignTokens.discharging,
                    icon: "laptopcomputer")
            }
        }
        .animation(.easeOut(duration: 0.35), value: battery)
        .animation(.easeOut(duration: 0.35), value: system)
    }

    /// Источник: мощность адаптера (или режим разрядки).
    private var adapterBlock: some View {
        VStack(spacing: DesignTokens.spacing1) {
            Image(systemName: data?.isPluggedIn == true
                  ? "powerplug.fill" : "battery.50")
                .font(.title3)
                .foregroundColor(DesignTokens.textSecondary)

            Text(adapterText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundColor(DesignTokens.textPrimary)

            Text(data?.isPluggedIn == true ? "адаптер" : "батарея")
                .font(.caption2)
                .foregroundColor(DesignTokens.textTertiary)
        }
        .frame(width: 74)
        .padding(.vertical, DesignTokens.spacing3)
        .liquidGlassBackground(level: 3, cornerRadius: DesignTokens.radius3)
    }

    private var adapterText: String {
        guard let data else { return "—" }
        if let adapterWatts = data.adapterWatts {
            return String(format: "%.0f W", adapterWatts)
        }
        return String(format: "%.1f W", system)
    }

    /// Полоса одного потребителя: подпись, значение, доля от шкалы.
    private func bar(
        label: String,
        value: Double,
        color: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            HStack(spacing: DesignTokens.spacing1) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(DesignTokens.textTertiary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(DesignTokens.textSecondary)
                Spacer()
                Text(String(format: "%.1f W", value))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))

                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.85), color.opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(
                            geometry.size.width * (value / scale), 2))
                }
            }
            .frame(height: 7)
        }
    }
}
