import SwiftUI
import AppKit

enum DS {

    enum Colors {
        static let canvas = adaptive(light: NSColor(srgbRed: 0.958, green: 0.958, blue: 0.972, alpha: 1),
                                     dark: NSColor(srgbRed: 0.096, green: 0.100, blue: 0.124, alpha: 1))
        static let cardSurface = adaptive(light: .white,
                                          dark: NSColor(srgbRed: 0.113, green: 0.122, blue: 0.157, alpha: 1))
        static let raisedSurface = adaptive(light: NSColor(srgbRed: 0.975, green: 0.975, blue: 0.985, alpha: 0.98),
                                            dark: NSColor(srgbRed: 0.125, green: 0.130, blue: 0.160, alpha: 0.97))
        static let textPrimary = adaptive(light: NSColor(srgbRed: 0.123, green: 0.141, blue: 0.177, alpha: 1),
                                          dark: NSColor(srgbRed: 0.907, green: 0.916, blue: 0.933, alpha: 1))
        static let textSecondary = adaptive(light: NSColor(srgbRed: 0.423, green: 0.448, blue: 0.497, alpha: 1),
                                            dark: NSColor(srgbRed: 0.590, green: 0.610, blue: 0.650, alpha: 1))
        static let textFaded = adaptive(light: NSColor(srgbRed: 0.123, green: 0.141, blue: 0.177, alpha: 0.42),
                                        dark: NSColor(srgbRed: 0.907, green: 0.916, blue: 0.933, alpha: 0.40))
        static let fillSubtle = adaptive(light: NSColor.black.withAlphaComponent(0.05),
                                         dark: NSColor.white.withAlphaComponent(0.06))
        static let fillHover = adaptive(light: NSColor.black.withAlphaComponent(0.07),
                                        dark: NSColor.white.withAlphaComponent(0.08))
        static let fillActive = adaptive(light: NSColor.black.withAlphaComponent(0.09),
                                         dark: NSColor.white.withAlphaComponent(0.10))
        static let hairline = adaptive(light: NSColor.black.withAlphaComponent(0.08),
                                       dark: NSColor.white.withAlphaComponent(0.09))
        static let glassStroke = adaptive(light: NSColor.white.withAlphaComponent(0.55),
                                          dark: NSColor.white.withAlphaComponent(0.10))
        static let edgeHighlight = adaptive(light: NSColor.white.withAlphaComponent(0.90),
                                            dark: NSColor.white.withAlphaComponent(0.06))
        static let accent = Color.accentColor
        static let warning = Color(nsColor: .systemOrange)
        static let danger = Color(nsColor: .systemRed)
        static let groupPalette: [Color] = [
            Color(nsColor: .systemOrange),
            Color(nsColor: .systemBlue),
            Color(nsColor: .systemGreen),
            Color(nsColor: .systemPurple),
            Color(nsColor: .systemPink),
            Color(nsColor: .systemTeal),
        ]

        private static func adaptive(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        }
    }

    enum Fonts {
        static let tabLabel = Font.system(size: 12.5)
        static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
        static let urlQuiet = Font.system(size: 12.5, weight: .medium)
        static let urlExpanded = Font.system(size: 12.5)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let counter = Font.system(size: 11).monospacedDigit()
        static let input = Font.system(size: 15)
        static let popoverHeader = Font.system(size: 13, weight: .semibold)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 10
        static let panel: CGFloat = 10
        static let control: CGFloat = 8
        static let row: CGFloat = 7
        static let favicon: CGFloat = 5
    }

    enum Shadows {
        static let cardColor = Colors.adaptiveShadow(lightAlpha: 0.10, darkAlpha: 0.30)
        static let cardRadius: CGFloat = 18
        static let cardY: CGFloat = 5
        static let overlayColor = Colors.adaptiveShadow(lightAlpha: 0.16, darkAlpha: 0.45)
        static let overlayRadius: CGFloat = 28
        static let overlayY: CGFloat = 9
    }

    enum Motion {
        static let snap = Animation.easeOut(duration: 0.10)
        static let fade = Animation.easeInOut(duration: 0.12)
        static let slide = Animation.easeInOut(duration: 0.18)
        static let peek = Animation.spring(response: 0.28, dampingFraction: 0.86)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 250
        static let headerHeight: CGFloat = 44
        static let cardMargin: CGFloat = 10
        static let controlSize: CGFloat = 29
        static let faviconSize: CGFloat = 16
        static let urlMaxWidth: CGFloat = 560
        static let hoverRevealDelay: TimeInterval = 0.15
    }
}

private extension DS.Colors {
    static func adaptiveShadow(lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let alpha = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkAlpha : lightAlpha
            return NSColor.black.withAlphaComponent(alpha)
        })
    }
}
