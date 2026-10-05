import Charts
import MediumWellBatteryCore
import SwiftUI

/// Вкладка «Графики»: три графика за последние 24 часа —
/// заряд, температура и потребление (DESIGN.md).
struct ChartsView: View {
    let data: ChartData

    var body: some View {
        VStack(spacing: DesignTokens.spacing3) {
            chargeCard
            temperatureCard
            powerCard

            if data.charge.isEmpty {
                Text("Нет данных за последние 24 часа")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Графики

    private var chargeCard: some View {
        chartCard(title: "Заряд", unit: "%", domain: 0...100) {
            ForEach(data.charge) { point in
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("Заряд", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DesignTokens.charging)
            }
        }
    }

    private var temperatureCard: some View {
        chartCard(title: "Температура", unit: "°C", domain: 0...50) {
            ForEach(data.temperature) { point in
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("Температура", point.value)
                )
                .interpolationMethod(.catmullRom)
                // Критический участок подсвечивается красным (FR-010).
                .foregroundStyle(
                    TemperatureState(value: point.value) == .critical
                        ? DesignTokens.critical
                        : DesignTokens.discharging)
            }
        }
    }

    private var powerCard: some View {
        chartCard(title: "Потребление", unit: "W", domain: nil) {
            ForEach(data.power) { point in
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("Мощность", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    point.isCharging
                        ? DesignTokens.charging
                        : DesignTokens.discharging)
            }
        }
    }

    // MARK: - Карточка графика

    /// Карточка одного графика: заголовок, единица измерения, область построения.
    @ViewBuilder
    private func chartCard<Content: ChartContent>(
        title: String, unit: String, domain: ClosedRange<Double>?,
        @ChartContentBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(unit)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Group {
                if let domain {
                    Chart { content() }
                        .chartYScale(domain: domain)
                } else {
                    Chart { content() }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading,
                          values: .automatic(desiredCount: 4))
            }
            .frame(height: 86)
        }
        .padding(DesignTokens.spacing3)
        .liquidGlassBackground(level: 2, cornerRadius: DesignTokens.radius3)
    }
}
