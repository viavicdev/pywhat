import SwiftUI
import AppKit

// Samme designspråk som TankeGeni / Ny Mappe 7 (apps/tankegeni/.../DesignTokens.swift)

private func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1.0)
    }))
}

private func adaptiveOpacity(
    light: (CGFloat, CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat, CGFloat)
) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
    }))
}

// Lys/mørk-innstilling: "auto" følger systemet, ellers overstyres hele appen.
// Design-fargene er dynamiske NSColors, så de reagerer på NSApp.appearance.
enum AppearanceMode {
    static let storageKey = "appearanceMode"

    static func apply(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func applySaved() {
        apply(UserDefaults.standard.string(forKey: storageKey) ?? "auto")
    }
}

enum Design {
    static let panelBackground     = adaptive(light: (0.97, 0.97, 0.96), dark: (0.04, 0.04, 0.06))
    static let cardBackground      = adaptive(light: (1.0, 1.0, 1.0),    dark: (0.09, 0.09, 0.12))
    static let cardHoverBackground = adaptive(light: (0.96, 0.96, 0.98), dark: (0.12, 0.12, 0.16))
    static let borderColor         = adaptiveOpacity(light: (0.0, 0.0, 0.0, 0.06), dark: (1.0, 1.0, 1.0, 0.08))
    static let subtleText          = adaptive(light: (0.50, 0.48, 0.52), dark: (0.48, 0.48, 0.55))
    static let primaryText         = adaptive(light: (0.06, 0.04, 0.10), dark: (0.96, 0.96, 0.98))
    static let accent              = adaptive(light: (0.85, 0.18, 0.22), dark: (0.95, 0.30, 0.32))
    static let successColor        = adaptive(light: (0.18, 0.60, 0.40), dark: (0.25, 0.78, 0.52))
    static let buttonTint          = adaptiveOpacity(light: (0.0, 0.0, 0.0, 0.05), dark: (1.0, 1.0, 1.0, 0.07))
    static let buttonTintPressed   = adaptiveOpacity(light: (0.0, 0.0, 0.0, 0.10), dark: (1.0, 1.0, 1.0, 0.14))
    static let buttonBorder        = adaptiveOpacity(light: (0.0, 0.0, 0.0, 0.08), dark: (1.0, 1.0, 1.0, 0.10))
    static let dividerColor        = adaptiveOpacity(light: (0.0, 0.0, 0.0, 0.08), dark: (1.0, 1.0, 1.0, 0.08))

    static let headingFont = Font.system(size: 14, weight: .bold,    design: .rounded)
    static let titleFont   = Font.system(size: 13, weight: .bold,    design: .rounded)
    static let bodyFont    = Font.system(size: 11, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 10, weight: .regular, design: .rounded)
    static let labelFont   = Font.system(size: 11, weight: .medium,  design: .rounded)

    static let cornerRadius:     CGFloat = 20
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding:      CGFloat = 14
    static let sectionSpacing:   CGFloat = 12

    // Seksjoner i prosess-panelet — egne SVG-er (asset) eller SF Symbols, ikke emojis
    struct Section {
        let key: String
        let title: String
        let symbol: String
        let color: Color
        var asset: String? = nil   // filnavn i Resources — overstyrer symbol
    }

    static let procSections: [Section] = [
        Section(key: "agents", title: "Agenter", symbol: "sparkles",
                color: Color(red: 0.910, green: 0.408, blue: 0.478),    // rose
                asset: "agents.svg"),
        Section(key: "cursor", title: "Cursor", symbol: "cursorarrow",
                color: Color(red: 0.482, green: 0.522, blue: 0.941),    // iris
                asset: "cursor.svg"),
        Section(key: "python", title: "Python", symbol: "chevron.left.forwardslash.chevron.right",
                color: Color(red: 0.910, green: 0.659, blue: 0.243)),   // amber
        Section(key: "node", title: "Node", symbol: "hexagon.fill",
                color: Color(red: 0.243, green: 0.812, blue: 0.698),    // teal
                asset: "node.svg"),
        Section(key: "tools", title: "Verktøy", symbol: "wrench.and.screwdriver.fill",
                color: Color(red: 0.427, green: 0.643, blue: 0.784)),   // slate
        Section(key: "apps", title: "Apper", symbol: "macwindow",
                color: Color(red: 0.788, green: 0.420, blue: 0.910)),   // plum
    ]

    static let dockerSection = Section(
        key: "docker", title: "Docker", symbol: "shippingbox.fill",
        color: Color(red: 0.941, green: 0.627, blue: 0.482)             // warm
    )

    struct PillButtonStyle: ButtonStyle {
        var isAccent: Bool = false
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    isAccent
                        ? Design.accent.opacity(configuration.isPressed ? 0.25 : 0.12)
                        : (configuration.isPressed ? Design.buttonTintPressed : Design.buttonTint)
                )
                .foregroundColor(isAccent ? Design.accent : Design.primaryText)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    isAccent ? Design.accent.opacity(0.25) : Design.buttonBorder,
                    lineWidth: 1
                ))
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    struct IconButtonStyle: ButtonStyle {
        var isAccent: Bool = false
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 11))
                .frame(width: 26, height: 22)
                .background(
                    isAccent
                        ? Design.accent.opacity(configuration.isPressed ? 0.25 : 0.12)
                        : (configuration.isPressed ? Design.buttonTintPressed : Design.buttonTint)
                )
                .foregroundColor(isAccent ? Design.accent : Design.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                    isAccent ? Design.accent.opacity(0.25) : Design.buttonBorder,
                    lineWidth: 1
                ))
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
