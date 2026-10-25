import AppKit
import SwiftUI

/// Design tokens. Every view takes its colours, type, spacing and radii from here (see DESIGN.md).
enum DK {
    // MARK: Colour (each token has a light and a dark value)
    
    static let background = Color(light: 0xFAFAF9, dark: 0x161618)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E1E21)
    static let surfaceHover = Color(light: 0xF2F2F0, dark: 0x26262A)
    static let border = Color(light: 0xE4E4E0, dark: 0x2E2E32)
    static let textPrimary = Color(light: 0x1A1A19, dark: 0xEDEDEC)
    static let textSecondary = Color(light: 0x6B6B68, dark: 0xA1A1A0)
    static let textTertiary = Color(light: 0x9C9C98, dark: 0x6E6E6C)
    /// Primary buttons are drawn inverted: text colour as background.
    static let inverseBackground = textPrimary
    static let inverseText = Color(light: 0xFFFFFF, dark: 0x161618)
    /// State colours are used for text only, never as fills.
    static let danger = Color(light: 0xC62828, dark: 0xF07A7A)
    static let warning = Color(light: 0x9A5B00, dark: 0xE8B04B)
    static let success = Color(light: 0x2E7D32, dark: 0x7BC47F)
    /// Switch track and knob when off; borders alone are too faint for a control.
    static let controlTrack = Color(light: 0xD6D6D2, dark: 0x3C3C41)
    static let controlKnob = Color(light: 0xFFFFFF, dark: 0x9C9C9A)
    /// Dims the window behind modal panels.
    static let scrim = Color.black.opacity(0.28)
    
    // MARK: Type (five sizes, no half points)
    
    enum Font {
        static let title = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let heading = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyMedium = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 12)
        static let micro = SwiftUI.Font.system(size: 11, weight: .medium)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }
    
    // MARK: Layout
    
    /// 4, 8, 12, 16, 24, 32 between elements; 2, 6 and 10 only for padding inside controls.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 10
        /// Elements nested inside a control (segment highlight, menu row).
        static let inner: CGFloat = 4
    }
    
    enum Icon {
        static let regular: CGFloat = 13
        /// Check marks and inline icons.
        static let small: CGFloat = 11
        /// Chevrons and the clear button inside a field.
        static let tiny: CGFloat = 9
    }
    
    static let controlHeight: CGFloat = 28
    static let compactControlHeight: CGFloat = 24
    static let pagePadding: CGFloat = 24
    static let sidebarWidth: CGFloat = 220
}

extension Color {
    /// A colour that follows the effective appearance (light or dark).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Appearance preference stored under `appearance`: follow the system, or force light or dark.
enum DKAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟隨系統"
        case .light: return "淺色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
