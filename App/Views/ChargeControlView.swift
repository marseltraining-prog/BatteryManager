import MediumWellBatteryCore
import SwiftUI

/// Управление зарядкой на вкладке «Статус» (FR-001..FR-003, FR-014):
/// слайдер лимита, режимы «Лимит» / «Разряд» / «Заряд» и честный статус —
/// успех показывается только после подтверждения контроллером.
struct ChargeControlView: View {
    @ObservedObject var manager: ChargeManager

    /// Значение слайдера во время перетаскивания: лимит применяется
    /// при отпускании, а не на каждом шаге.
    @State private var draftLimit: Double?

    private var shownLimit: Int {
        draftLimit.map { Int($0.rounded()) } ?? manager.limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            HStack {
                Text("Лимит заряда")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignTokens.textPrimary)
                Spacer()
                Text(shownLimit >= 100 ? "выключен" : "\(shownLimit)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundColor(DesignTokens.charging)
            }

            if manager.availableLimits.isEmpty {
                limitSlider
            } else {
                // Лимит держит macOS и принимает только эти значения.
                HStack(spacing: DesignTokens.spacing2) {
                    ForEach(manager.availableLimits, id: \.self) { value in
                        limitButton(value)
                    }
                }
            }

            HStack(spacing: DesignTokens.spacing2) {
                modeButton(.limit, "Лимит", "gauge.medium",
                           help: "Заряжать до установленного лимита")
                modeButton(.forceDischarge, "Разряд", "minus.circle",
                           help: manager.canHold
                               ? "Не заряжать, пока режим не отменён"
                               : manager.holdUnavailableReason
                                   ?? "Остановка зарядки недоступна")
                    .disabled(!manager.canHold)
                    .opacity(manager.canHold ? 1 : 0.45)
                modeButton(.forceCharge, "Заряд", "plus.circle",
                           help: "Зарядить до 100% без учёта лимита")
            }

            statusLine
        }
        .disabled(!manager.isSupported)
        .padding(DesignTokens.spacing4)
        .liquidGlassBackground(level: 2, cornerRadius: DesignTokens.radius3)
    }

    private var limitSlider: some View {
        Slider(
            value: Binding(
                get: { draftLimit ?? Double(manager.limit) },
                set: { draftLimit = $0 }),
            in: 20...100
        ) { editing in
            if !editing, let draft = draftLimit {
                manager.setLimit(Int(draft.rounded()))
                draftLimit = nil
            }
        }
        .tint(DesignTokens.charging)
        .accessibilityLabel("Лимит заряда")
        .accessibilityValue("\(shownLimit) процентов")
    }

    private func limitButton(_ value: Int) -> some View {
        let isActive = manager.limit == value
        return Button {
            manager.setLimit(value)
        } label: {
            Text(value >= 100 ? "Выкл" : "\(value)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(isActive
                    ? DesignTokens.charging : DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    Capsule().fill(isActive
                        ? DesignTokens.charging.opacity(0.2)
                        : DesignTokens.surface3))
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? DesignTokens.charging.opacity(0.4)
                                 : Color.white.opacity(0.1),
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(value >= 100 ? "Заряжать до 100%" : "Заряжать до \(value)%")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func modeButton(_ mode: ChargeMode, _ title: String,
                            _ icon: String, help: String) -> some View {
        let isActive = manager.mode == mode
        return Button {
            manager.setMode(mode)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundColor(isActive
                    ? DesignTokens.charging : DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    Capsule().fill(isActive
                        ? DesignTokens.charging.opacity(0.2)
                        : DesignTokens.surface3))
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? DesignTokens.charging.opacity(0.4)
                                 : Color.white.opacity(0.1),
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Статус

    @ViewBuilder
    private var statusLine: some View {
        switch manager.status {
        case .unsupported:
            statusText(manager.unavailableReason
                       ?? "Управление зарядкой недоступно",
                       icon: "xmark.octagon", color: DesignTokens.textTertiary)

        case .failed(let message):
            VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                statusText("Команда не выполнена — зарядкой управляет система",
                           icon: "exclamationmark.triangle",
                           color: DesignTokens.warning)
                Text(message)
                    .font(.caption2)
                    .foregroundColor(DesignTokens.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Повторить") { manager.retry() }
                    .font(.caption)
            }

        case .idle:
            statusText(manager.limit >= 100 && manager.mode == .limit
                       ? "Лимит не задан — зарядкой управляет система"
                       : "Ожидание данных батареи",
                       icon: "info.circle", color: DesignTokens.textTertiary)

        case .confirmed(let allowed):
            if allowed {
                statusText(allowedText, icon: allowedIcon,
                           color: DesignTokens.charging)
            } else {
                statusText(holdText, icon: "pause.circle.fill",
                           color: manager.holdReason == .overheat
                               ? DesignTokens.critical : DesignTokens.warning)
            }
        }
    }

    private var allowedText: String {
        guard manager.usesSystemLimit else { return "Зарядка разрешена" }
        if manager.mode == .forceCharge {
            return "Заряд до 100%, затем вернётся лимит \(manager.limit)%"
        }
        if manager.limit >= 100 {
            return "Лимит выключен — заряд до 100%"
        }
        if let charge = manager.lastCharge, charge > manager.limit {
            return "Заряд выше лимита — macOS снизит его до \(manager.limit)%"
        }
        return manager.holdReason == .limit
            ? "macOS держит заряд на лимите \(manager.limit)%"
            : "macOS зарядит до \(manager.limit)% и остановится"
    }

    private var allowedIcon: String {
        manager.holdReason == .limit ? "checkmark.shield.fill" : "bolt.fill"
    }

    private var holdText: String {
        switch manager.holdReason {
        case .overheat: return "Зарядка остановлена: перегрев батареи"
        case .manual: return "Зарядка остановлена вручную"
        case .limit, .none: return "Зарядка остановлена на лимите \(manager.limit)%"
        }
    }

    private func statusText(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
