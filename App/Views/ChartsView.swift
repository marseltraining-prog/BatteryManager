import Charts
import MediumWellBatteryCore
import SwiftUI

/// Вкладка «Графики»: три графика за последние 24 часа —
/// заряд (%), температура (°C) и потребление (Вт).
struct ChartsView: View {
    let data: ChartData
    var historyUnavailable: Bool = false

    /// Точка под курсором: какой график и индекс точки (FR-015).
    @State private var hover: (chart: String, index: Int)?

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
                 + "Разрыв линии — приложение не работало. "
                 + "Наведите курсор на график, чтобы увидеть значение.")
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
            domain: 0...100,
            dates: data.charge.map(\.date),
            valueText: { "\(data.charge[$0].value)%" }
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
            domain: 0...50,
            dates: data.temperature.map(\.date),
            valueText: { String(format: "%.1f °C", data.temperature[$0].value) }
        ) {
            // Зоны перегрева (FR-008): пороги предупреждения и критики.
            RuleMark(y: .value("Предупреждение", 35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(DesignTokens.warning.opacity(0.5))
            RuleMark(y: .value("Критично", 40))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(DesignTokens.critical.opacity(0.5))

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
            domain: nil,
            dates: data.power.map(\.date),
            valueText: { String(format: "%+.1f Вт", data.power[$0].value) }
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

    /// Вертикальная линия на точке под курсором.
    @ChartContentBuilder
    private func hoverRule(_ date: Date?) -> some ChartContent {
        if let date {
            RuleMark(x: .value("Время", date))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    /// Карточка одного графика: название, текущее значение, оси с подписями.
    @ViewBuilder
    private func chartCard<Content: ChartContent>(
        title: String,
        unit: String,
        currentValue: String?,
        domain: ClosedRange<Double>?,
        dates: [Date],
        valueText: @escaping (Int) -> String,
        @ChartContentBuilder content: () -> Content
    ) -> some View {
        // Данные могли обновиться, пока курсор над графиком.
        let hoveredIndex = hover.flatMap {
            $0.chart == title && $0.index < dates.count ? $0.index : nil
        }
        let hoveredDate = hoveredIndex.map { dates[$0] }
        let headerValue = hoveredIndex.map {
            "\(dates[$0].formatted(date: .omitted, time: .shortened))  "
                + valueText($0)
        } ?? currentValue

        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignTokens.textPrimary)
                Spacer()
                if let headerValue {
                    Text(headerValue)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(hoveredIndex == nil
                            ? DesignTokens.textPrimary : DesignTokens.charging)
                }
            }

            Group {
                if let domain {
                    Chart { content(); hoverRule(hoveredDate) }
                        .chartYScale(domain: domain)
                } else {
                    Chart { content(); hoverRule(hoveredDate) }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let x = location.x
                                    - geometry[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x),
                                   let index = ChartData.nearestIndex(
                                    to: date, in: dates) {
                                    hover = (title, index)
                                } else {
                                    hover = nil
                                }
                            case .ended:
                                hover = nil
                            }
                        }
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
