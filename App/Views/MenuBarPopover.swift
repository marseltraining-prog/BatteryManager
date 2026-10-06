import MediumWellBatteryCore
import SwiftUI

/// Главное всплывающее окно: шапка, вкладки и содержимое выбранной вкладки.
struct MenuBarPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: DesignTokens.spacing3) {
            header
            tabPicker
            content
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.spacing4)
        // Размер окна по спеке (FR-013): 420×680.
        .frame(width: 420, height: 680)
        .background(DesignTokens.surface1)
        // Тёмная тема обязательна: стекло тёмное, при светлой теме
        // системные подписи становились чёрными на чёрном.
        .preferredColorScheme(.dark)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            Text("BatteryManager")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignTokens.textSecondary)

            Spacer()

            if let data = model.batteryService.currentData {
                if let temperature = data.temperature {
                    Text(String(format: "%.1f°C", temperature))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(temperatureColor(temperature))
                }
                Text("\(data.currentCharge)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(DesignTokens.textPrimary)
            }
        }
    }

    // MARK: - Вкладки

    private var tabPicker: some View {
        Picker("", selection: $model.selectedTab) {
            ForEach(PopoverTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        switch model.selectedTab {
        case .status:
            ScrollView {
                StatusView(data: model.batteryService.currentData,
                           chargeManager: model.chargeManager)
            }

        case .charts:
            ScrollView {
                ChartsView(data: model.chartData,
                           historyUnavailable: model.historyUnavailable)
            }
            .frame(height: 520)

        case .health:
            HealthView(data: model.batteryService.currentData)
        }
    }

    private func temperatureColor(_ temperature: Double) -> Color {
        switch TemperatureState(value: temperature) {
        case .normal: return DesignTokens.textSecondary
        case .warning: return DesignTokens.warning
        case .critical: return DesignTokens.critical
        }
    }
}
