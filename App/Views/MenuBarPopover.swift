import SwiftUI
import MediumWellBatteryCore

/// Главное всплывающее окно приложения: вкладка «Статус».
/// Вкладки «Графики» и «Здоровье» добавляются следующими задачами плана.
struct MenuBarPopover: View {
    @ObservedObject var batteryService: BatteryService

    var body: some View {
        VStack(spacing: DesignTokens.spacing4) {
            // Заголовок окна.
            HStack {
                Text("BatteryManager")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let data = batteryService.currentData {
                    Text("\(data.currentCharge)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            StatusView(data: batteryService.currentData)
        }
        .padding(DesignTokens.spacing4)
        .frame(width: 420)
        .background(DesignTokens.surface1)
    }
}
