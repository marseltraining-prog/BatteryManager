import SwiftUI
import Testing
@testable import MediumWellBatteryCore

@Suite
struct DesignTokensTests {
    // MARK: - Color(hex:)

    @Test func hexInitParsesChargingGreen() {
        #expect(Color(hex: "6EE7B7")
            == Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255))
    }

    @Test func hexInitParsesDischargingBlue() {
        #expect(Color(hex: "38BDF8")
            == Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255))
    }

    @Test func hexInitParsesWarningAmber() {
        #expect(Color(hex: "FBBF24")
            == Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255))
    }

    @Test func hexInitParsesCriticalRed() {
        #expect(Color(hex: "F87171")
            == Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255))
    }

    // MARK: - Акценты по DESIGN.md

    @Test func accentTokensMatchDesignDocument() {
        #expect(DesignTokens.charging == Color(hex: "6EE7B7"))
        #expect(DesignTokens.discharging == Color(hex: "38BDF8"))
        #expect(DesignTokens.warning == Color(hex: "FBBF24"))
        #expect(DesignTokens.critical == Color(hex: "F87171"))
        #expect(DesignTokens.overheat == Color(hex: "FB923C"))
    }

    // MARK: - Поверхности и геометрия

    @Test func surfacesFormDeepToLightStack() {
        // 5 уровней поверхностей Liquid Glass: от глубокого к светлому.
        #expect(DesignTokens.surface1 != DesignTokens.surface5)
        #expect(DesignTokens.spacing1 < DesignTokens.spacing6)
        #expect(DesignTokens.radius1 < DesignTokens.radius4)
        #expect(DesignTokens.radiusPill > DesignTokens.radius4)
    }
}
