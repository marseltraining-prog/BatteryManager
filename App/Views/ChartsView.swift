import Charts
import MediumWellBatteryCore
import SwiftUI

/// Вкладка «Графики»: три графика за последние 24 часа —
/// заряд, температура и потребление (FR-007, FR-008, FR-009).
struct ChartsView: View {
    let data: ChartData
    var historyUnavailable: Bool = false

    var body: some View {
        VStack(spacing: DesignTokens.spacing3) {
            if historyUnavailable {
                // Ошибка чтения истории не должна выглядеть как «нет данных».
                Label("История недоступна — не удалось прочитать базу",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(DesignTokens.warning)
                    .frame(maxWidth: .infinity)
            }

            chargeCard
            temperatureCard
            powerCard

            if data.charge.isEmpty && !historyUnavailable {
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
                // Заливка под линией (FR-007).
                AreaMark(
                    x: .value("Время", point.date),
                    y: .value("Заряд", point.value),
                    series: .value("Серия", point.segment)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.charging.opacity(0.35), .clear],
                        startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Время", point.date),
                    y: .value("Заряд", point.value),
                    series: .value("Серия", point.segment)
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
                    y: .value("Температура", point.value),
                    series: .value("Серия", point.segment)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(temperatureColor(point.value))
            }
        }
    }

    private var powerCard: some View {
        chartCard(title: "Потребление", unit: "W", domain: nil) {
            ForEach(data.power) { point in
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("Мощность", point.value),
                    series: .value("Серия", point.segment)
                )
                .interpolationMethod(.catmullRom)
                // Плюс — зарядка (зелёный), минус — разрядка (голубой), FR-009.
                .foregroundStyle(
                    point.value >= 0 ? DesignTokens.charging : DesignTokens.discharging)
            }
        }
    }

    /// Цветовая шкала температуры (FR-008): норма → предупреждение → критика.
    private func temperatureColor(_ value: Double) -> Color {
        switch TemperatureState(value: value) {
        case .normal: return DesignTokens.discharging
        case .warning: return DesignTokens.warning
        case .critical: return DesignTokens.critical
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
        .liquidGlassBackground(level: 2, cornerRadius: DesignTokens.radius2)
    }
}
