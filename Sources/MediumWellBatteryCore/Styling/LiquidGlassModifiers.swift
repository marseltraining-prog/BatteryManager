import SwiftUI

// MARK: - Liquid Glass модификаторы (см. DESIGN.md)

public extension View {
    /// Стеклянная подложка: полупрозрачная поверхность уровня 1...5,
    /// градиентная рамка «света» и многослойная тень для глубины.
    func liquidGlassBackground(
        level: Int = 1,
        cornerRadius: CGFloat = DesignTokens.radius3
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DesignTokens.surface(for: level))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: .white.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    /// Стеклянная кнопка-«пилюля» (уровень 3, скругление pill).
    func glassButton() -> some View {
        self
            .padding(.horizontal, DesignTokens.spacing3)
            .padding(.vertical, DesignTokens.spacing2)
            .liquidGlassBackground(level: 3, cornerRadius: DesignTokens.radiusPill)
    }

    /// Стеклянная карточка (уровень 2, внутренние отступы 20, радиус 24).
    func glassCard() -> some View {
        self
            .padding(DesignTokens.spacing5)
            .liquidGlassBackground(level: 2, cornerRadius: DesignTokens.radius4)
    }
}
