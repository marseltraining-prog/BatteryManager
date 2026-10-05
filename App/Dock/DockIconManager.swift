import AppKit
import Combine
import MediumWellBatteryCore
import SwiftUI

/// Иконка в Dock: процент заряда на плитке и цвет по состоянию (FR-012).
///
/// Цвета: зарядка — зелёный, разрядка — белый, предупреждение о нагреве —
/// янтарь с ⚠️, критический перегрев — красный с 🔥.
final class DockIconManager {
    private let batteryService: BatteryService
    private let temperatureMonitor: TemperatureMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(batteryService: BatteryService, temperatureMonitor: TemperatureMonitor) {
        self.batteryService = batteryService
        self.temperatureMonitor = temperatureMonitor

        // Плитка Dock доступна только «обычному» приложению.
        // Откладываем на главную очередь: на момент создания модели
        // NSApplication ещё достраивается.
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            self.update()
        }

        // Dock сбрасывает contentView при запуске — перерисовываем после него.
        NotificationCenter.default.publisher(
            for: NSApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        batteryService.$currentData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        temperatureMonitor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    /// Перерисовывает плитку Dock текущими данными.
    func update() {
        let data = batteryService.currentData
        let view = DockIconView(
            charge: data?.currentCharge,
            isCharging: data?.isCharging ?? false,
            state: temperatureMonitor.state)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 128, height: 128)

        NSApplication.shared.dockTile.contentView = hosting
        NSApplication.shared.dockTile.display()
    }
}

/// Содержимое плитки Dock: процент заряда и значок состояния.
struct DockIconView: View {
    let charge: Int?
    let isCharging: Bool
    let state: TemperatureState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(DesignTokens.surface1)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(DesignTokens.glassBorder, lineWidth: 2)

            VStack(spacing: 0) {
                Text(charge.map { "\($0)%" } ?? "--%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 26))
                }
            }
            .padding(6)
        }
        .frame(width: 128, height: 128)
    }

    /// Цвет процента по состоянию батареи.
    private var tint: Color {
        switch state {
        case .critical: return DesignTokens.critical
        case .warning: return DesignTokens.warning
        case .normal: return isCharging ? DesignTokens.charging : .white
        }
    }

    /// Значок состояния: молния, предупреждение или перегрев.
    private var badge: String {
        switch state {
        case .critical: return "🔥"
        case .warning: return "⚠️"
        case .normal: return isCharging ? "⚡" : ""
        }
    }
}
