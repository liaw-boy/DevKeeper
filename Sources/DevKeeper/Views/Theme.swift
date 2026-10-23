import SwiftUI

public struct Theme {
    // Canvas & Surfaces
    public static let canvasBackground = Color(red: 0.07, green: 0.08, blue: 0.09)
    public static let cardBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    public static let cardBackgroundHover = Color(red: 0.14, green: 0.15, blue: 0.19)
    public static let elevatedBackground = Color(red: 0.15, green: 0.16, blue: 0.20)
    
    // UsageView Warm Charcoal & Slate Theme (Exact Sampled Values)
    public static let usageWindowBg = Color(red: 0.145, green: 0.153, blue: 0.173) // #25272c
    public static let usageCardBg = Color(red: 0.188, green: 0.196, blue: 0.220)   // #303238
    public static let usageCardBorder = Color(red: 0.243, green: 0.255, blue: 0.286) // #3e4149
    public static let usagePillBg = Color(red: 0.212, green: 0.220, blue: 0.247)   // #36383f
    public static let usageRowBg = Color(red: 0.235, green: 0.243, blue: 0.267)    // #3c3e44
    public static let usageActivePill = Color(red: 0.267, green: 0.278, blue: 0.310) // #44474f
    
    // UsageView Vibrant Accents
    public static let usageOrange = Color(red: 0.918, green: 0.435, blue: 0.278)   // #ea6f47
    public static let usageGreen = Color(red: 0.239, green: 0.847, blue: 0.553)    // #3dd88d
    public static let usageBlue = Color(red: 0.322, green: 0.514, blue: 0.961)     // #5283f5
    public static let usagePurple = Color(red: 0.600, green: 0.350, blue: 0.960)   // #9959f5
    
    // Borders & Dividers (Subtle metallic/glass highlights)
    public static let subtleBorder = Color.white.opacity(0.07)
    public static let highlightBorder = Color.white.opacity(0.13)
    
    // Accents & Gradients (Linear / Raycast modern palette)
    public static let primaryIndigo = Color(red: 0.36, green: 0.44, blue: 0.98)
    public static let primaryIndigoDark = Color(red: 0.25, green: 0.32, blue: 0.88)
    
    public static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.40, green: 0.48, blue: 1.0), Color(red: 0.28, green: 0.35, blue: 0.92)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let cardGradient = LinearGradient(
        colors: [Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.09, green: 0.10, blue: 0.13)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Semantic States
    public static let successGreen = Color(red: 0.24, green: 0.80, blue: 0.54)
    public static let warningAmber = Color(red: 0.98, green: 0.68, blue: 0.28)
    public static let dangerRed = Color(red: 0.96, green: 0.38, blue: 0.38)
    public static let infoCyan = Color(red: 0.28, green: 0.72, blue: 0.94)
    public static let purpleAccent = Color(red: 0.65, green: 0.45, blue: 0.98)
}

// MARK: - Emil Kowalski Micro-interaction Button Styles
public struct BouncyButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.97
    
    public init(scale: CGFloat = 0.97) {
        self.scale = scale
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    public static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
    public static func bouncy(scale: CGFloat) -> BouncyButtonStyle { BouncyButtonStyle(scale: scale) }
}
