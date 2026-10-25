import DevKeeperCore
import SwiftUI

public struct Theme {
    // Canvas & Surfaces
    public static let canvasBackground = Color(red: 0.07, green: 0.08, blue: 0.09)
    public static let cardBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    public static let cardBackgroundHover = Color(red: 0.14, green: 0.15, blue: 0.19)
    
    // Borders & Dividers (Subtle metallic/glass highlights)
    public static let subtleBorder = Color.white.opacity(0.07)
    public static let highlightBorder = Color.white.opacity(0.13)
    
    // Accents & Gradients (Linear / Raycast modern palette)
    public static let primaryIndigo = Color(red: 0.36, green: 0.44, blue: 0.98)
    
    public static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.40, green: 0.48, blue: 1.0), Color(red: 0.28, green: 0.35, blue: 0.92)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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
