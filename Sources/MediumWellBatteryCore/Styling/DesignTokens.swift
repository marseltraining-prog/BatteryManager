import SwiftUI

/// Дизайн-токены Liquid Glass — единый источник цветов, геометрии и отступов.
/// Значения соответствуют DESIGN.md.
public enum DesignTokens {
    // MARK: - Поверхности (Liquid Glass: полупрозрачные, от глубокого к светлому)

    /// Самый глубокий уровень: основной фон окна.
    public static let surface1 = Color(red: 5 / 255, green: 7 / 255, blue: 12 / 255)
        .opacity(0.85)
    /// Карточки и панели.
    public static let surface2 = Color(red: 10 / 255, green: 13 / 255, blue: 18 / 255)
        .opacity(0.75)
    /// Элементы управления.
    public static let surface3 = Color(red: 15 / 255, green: 19 / 255, blue: 28 / 255)
        .opacity(0.65)
    /// Ховер-состояния.
    public static let surface4 = Color(red: 22 / 255, green: 29 / 255, blue: 43 / 255)
        .opacity(0.55)
    /// Акценты.
    public static let surface5 = Color(red: 30 / 255, green: 38 / 255, blue: 54 / 255)
        .opacity(0.45)

    /// Поверхность по уровню 1...5.
    public static func surface(for level: Int) -> Color {
        switch level {
        case 1: return surface1
        case 2: return surface2
        case 3: return surface3
        case 4: return surface4
        default: return surface5
        }
    }

    // MARK: - Акценты

    /// Зарядка — светящийся изумруд.
    public static let charging = Color(hex: "6EE7B7")
    /// Разрядка — циановый акцент.
    public static let discharging = Color(hex: "38BDF8")
    /// Предупреждение о температуре (35-40°C) — тёплый янтарь.
    public static let warning = Color(hex: "FBBF24")
    /// Критический перегрев (>40°C) — мягкий красный.
    public static let critical = Color(hex: "F87171")
    /// Перегрев — тёплый оранжевый.
    public static let overheat = Color(hex: "FB923C")

    // MARK: - Текст

    // Явные цвета текста вместо системного `.secondary`: при светлой
    // системной теме он тёмный и на стекле превращается в «чёрное на чёрном».

    /// Основной текст.
    public static let textPrimary = Color.white.opacity(0.95)
    /// Подписи и второстепенные значения.
    public static let textSecondary = Color.white.opacity(0.70)
    /// Оси графиков и сноски.
    public static let textTertiary = Color.white.opacity(0.50)

    // MARK: - Градиенты

    /// Градиент индикатора заряда.
    public static let chargeGradient = LinearGradient(
        colors: [Color(hex: "6EE7B7"), Color(hex: "10B981")],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Стеклянная рамка: свет сверху-слева гаснет к низу-справа.
    public static let glassBorder = LinearGradient(
        colors: [.white.opacity(0.2), .white.opacity(0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: - Отступы

    public static let spacing1: CGFloat = 4
    public static let spacing2: CGFloat = 8
    public static let spacing3: CGFloat = 12
    public static let spacing4: CGFloat = 16
    public static let spacing5: CGFloat = 20
    public static let spacing6: CGFloat = 24

    // MARK: - Радиусы скругления

    public static let radius1: CGFloat = 8
    public static let radius2: CGFloat = 12
    public static let radius3: CGFloat = 16
    public static let radius4: CGFloat = 24
    /// Полностью скруглённая кнопка-«пилюля».
    public static let radiusPill: CGFloat = 999
}

public extension Color {
    /// Цвет из HEX-строки вида `"6EE7B7"` (без префикса `#`).
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
