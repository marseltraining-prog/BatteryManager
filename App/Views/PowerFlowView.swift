import MediumWellBatteryCore
import SwiftUI

/// Поток энергии (FR-005): слева источник, от него расходятся ленты
/// «в батарею» и «в систему». Ширина ленты пропорциональна мощности,
/// поэтому сразу видно, куда уходит энергия.
struct PowerFlowView: View {
    let data: BatteryInfo

    private var flow: PowerFlow { PowerFlow(data) }

    private let height: CGFloat = 150
    private let sourceWidth: CGFloat = 70
    private let targetWidth: CGFloat = 54
    private let gap: CGFloat = 6
    /// Лента и блок не становятся тоньше этого — иначе подпись не читается.
    private let minBand: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(
                flow: flow, size: geometry.size, sourceWidth: sourceWidth,
                targetWidth: targetWidth, gap: gap, minBand: minBand)

            ZStack(alignment: .topLeading) {
                sourceBlock
                    .frame(width: sourceWidth, height: geometry.size.height)

                if layout.showsBattery {
                    // На лимите батарея не заряжается: блок остаётся,
                    // но приглушён, и лента к нему не идёт.
                    if flow.toBattery > 0 {
                        ribbon(layout.battery, color: DesignTokens.charging,
                               watts: flow.toBattery, layout: layout)
                    }
                    targetBlock(flow.toBattery > 0
                                    ? "battery.100.bolt" : "battery.100",
                                color: flow.toBattery > 0
                                    ? DesignTokens.charging
                                    : DesignTokens.textTertiary,
                                band: layout.battery, layout: layout)
                }

                ribbon(layout.system, color: DesignTokens.discharging,
                       watts: flow.toSystem, layout: layout)
                targetBlock("laptopcomputer", color: DesignTokens.discharging,
                            band: layout.system, layout: layout)
            }
            .animation(.easeOut(duration: 0.45), value: flow)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Источник

    private var sourceBlock: some View {
        VStack(spacing: DesignTokens.spacing1) {
            Image(systemName: flow.source == .adapter
                  ? "powerplug.fill" : "battery.75")
                .font(.title3)
                .foregroundColor(DesignTokens.textPrimary)

            Text(sourceText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundColor(DesignTokens.textPrimary)

            Text(flow.source == .adapter ? "адаптер" : "батарея")
                .font(.caption2)
                .foregroundColor(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.radius3, style: .continuous)
                .fill(DesignTokens.surface4))
    }

    /// У адаптера — паспортная мощность, у батареи — сколько она отдаёт.
    private var sourceText: String {
        if flow.source == .adapter, let rated = data.adapterWatts {
            return String(format: "%.0f W", rated)
        }
        return String(format: "%.1f W", flow.total)
    }

    // MARK: - Ленты и приёмники

    private func ribbon(_ band: Layout.Band, color: Color, watts: Double,
                        layout: Layout) -> some View {
        Ribbon(leftTop: band.leftTop, leftBottom: band.leftBottom,
               rightTop: band.rightTop, rightBottom: band.rightBottom)
            .fill(LinearGradient(
                stops: [
                    .init(color: color.opacity(0.10), location: 0),
                    .init(color: color.opacity(0.70), location: 0.62),
                    .init(color: Color.white.opacity(0.10), location: 0.66),
                    .init(color: Color.white.opacity(0.07), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: layout.ribbonWidth, height: layout.size.height)
            .overlay(
                Text(String(format: "%.1f W", watts))
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundColor(DesignTokens.textPrimary)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .position(x: layout.ribbonWidth * 0.5,
                              y: (band.leftMid + band.rightMid) / 2)
            )
            .offset(x: layout.ribbonX)
    }

    private func targetBlock(_ icon: String, color: Color, band: Layout.Band,
                             layout: Layout) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundColor(color)
            .frame(width: targetWidth, height: band.rightBottom - band.rightTop)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.radius3,
                                 style: .continuous)
                    .fill(DesignTokens.surface4))
            .offset(x: layout.targetX, y: band.rightTop)
    }

    private var accessibilityText: String {
        let source = flow.source == .adapter ? "Питание от адаптера" : "Питание от батареи"
        return String(format: "%@. В батарею %.1f ватт, система %.1f ватт",
                      source, flow.toBattery, flow.toSystem)
    }
}

// MARK: - Геометрия

private struct Layout {
    /// Вертикальные границы ленты слева (у источника) и справа (у приёмника).
    struct Band {
        var leftTop: CGFloat = 0
        var leftBottom: CGFloat = 0
        var rightTop: CGFloat = 0
        var rightBottom: CGFloat = 0

        var leftMid: CGFloat { (leftTop + leftBottom) / 2 }
        var rightMid: CGFloat { (rightTop + rightBottom) / 2 }
    }

    let size: CGSize
    let ribbonX: CGFloat
    let ribbonWidth: CGFloat
    let targetX: CGFloat
    let showsBattery: Bool
    var battery = Band()
    var system = Band()

    init(flow: PowerFlow, size: CGSize, sourceWidth: CGFloat,
         targetWidth: CGFloat, gap: CGFloat, minBand: CGFloat) {
        self.size = size
        ribbonX = sourceWidth + gap
        ribbonWidth = max(size.width - sourceWidth - targetWidth - gap * 2, 0)
        targetX = size.width - targetWidth
        // Блок батареи показывается всегда, когда питает адаптер.
        showsBattery = flow.source == .adapter

        let height = size.height
        guard showsBattery else {
            // Питает батарея: один потребитель, лента на всю высоту.
            system = Band(leftTop: 0, leftBottom: height,
                          rightTop: 0, rightBottom: height)
            return
        }

        guard flow.toBattery > 0 else {
            // На лимите: вся мощность адаптера идёт в систему.
            let blockBottom = minBand + 8
            battery = Band(leftTop: 0, leftBottom: 0,
                           rightTop: 0, rightBottom: blockBottom)
            system = Band(leftTop: 0, leftBottom: height,
                          rightTop: blockBottom + gap, rightBottom: height)
            return
        }

        // Слева ленты выходят из источника вплотную, справа — с зазором
        // между блоками. Доля ограничена, чтобы узкая лента читалась.
        let share = CGFloat(flow.batteryShare)
        let leftSplit = min(max(height * share, minBand), height - minBand)
        let usable = height - gap
        let rightSplit = min(max(usable * share, minBand), usable - minBand)

        battery = Band(leftTop: 0, leftBottom: leftSplit,
                       rightTop: 0, rightBottom: rightSplit)
        system = Band(leftTop: leftSplit, leftBottom: height,
                      rightTop: rightSplit + gap, rightBottom: height)
    }
}

/// Лента потока: слева и справа свои вертикальные границы, между ними —
/// плавный изгиб.
private struct Ribbon: Shape {
    var leftTop: CGFloat
    var leftBottom: CGFloat
    var rightTop: CGFloat
    var rightBottom: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(leftTop, leftBottom),
                           AnimatablePair(rightTop, rightBottom))
        }
        set {
            leftTop = newValue.first.first
            leftBottom = newValue.first.second
            rightTop = newValue.second.first
            rightBottom = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let middle = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: leftTop))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rightTop),
                      control1: CGPoint(x: middle, y: leftTop),
                      control2: CGPoint(x: middle, y: rightTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: rightBottom))
        path.addCurve(to: CGPoint(x: rect.minX, y: leftBottom),
                      control1: CGPoint(x: middle, y: rightBottom),
                      control2: CGPoint(x: middle, y: leftBottom))
        path.closeSubpath()
        return path
    }
}
