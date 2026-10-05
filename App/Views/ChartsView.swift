import Charts
import MediumWellBatteryCore
import SwiftUI

/// Вкладка «Графики»: три графика за последние 24 часа —
/// заряд (%), температура (°C) и потребление (Вт).
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

            Text("Данные за последние 24 часа, запись раз в минуту. "
                 + "Разрыв линии — приложение не работало.")
                .font(.caption2)
                .foregroundColor(DesignTokens.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if data.charge.isEmpty && !historyUnavailable {
                Text("Нет данных за последние 24 часа")
                    .font(.caption)
                    .foregroundColor(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Графики

    private var chargeCard: some View {
        chartCard(
            title: "Заряд батареи",
            unit: "%",
            currentValue: data.charge.last.map { "\($0.value)%" },
            domain: 0...100
        ) {
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
        chartCard(
            title: "Температура батареи",
            unit: "°C",
            currentValue: data.temperature.last.map { String(format: "%.1f °C", $0.value) },
            domain: 0...50
        ) {
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
        chartCard(
            title: "Мощность: + зарядка / − разрядка",
            unit: "Вт",
            currentValue: data.power.last.map {
                String(format: "%+.1f Вт", $0.value)
            },
            domain: nil
        ) {
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

    /// Карточка одного графика: название, текущее значение, оси с подписями.
    @ViewBuilder
    private func chartCard<Content: ChartContent>(
        title: String,
        unit: String,
        currentValue: String?,
        domain: ClosedRange<Double>?,
        @ChartContentBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignTokens.textPrimary)
                Spacer()
                if let currentValue {
                    Text(currentValue)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(DesignTokens.textPrimary)
                }
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
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisTick().foregroundStyle(Color.white.opacity(0.2))
                    // Подписи времени: без них непонятно, что за период.
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .frame(height: 92)

            Text(unit)
                .font(.caption2)
                .foregroundColor(DesignTokens.textTertiary)
        }
        .padding(DesignTokens.spacing3)
        .liquidGlassBackground(level: 2, cornerRadius: DesignTokens.radius2)
    }
}
