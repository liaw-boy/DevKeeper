import SwiftUI

/// Official GitHub Octocat Logo Shape rendered via SVG vector path
public struct GitHubMarkShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let scaleX = rect.width / 16.0
        let scaleY = rect.height / 16.0
        let scale = min(scaleX, scaleY)
        
        let offsetX = (rect.width - 16.0 * scale) / 2.0
        let offsetY = (rect.height - 16.0 * scale) / 2.0
        
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: offsetX + x * scale, y: offsetY + (16.0 - y) * scale)
        }
        
        // Exact GitHub Octocat Path scaled to 16x16
        path.move(to: pt(8, 16))
        path.addCurve(to: pt(0, 8), control1: pt(3.58, 16), control2: pt(0, 12.42))
        path.addCurve(to: pt(5.47, 0.41), control1: pt(0, 4.46), control2: pt(2.29, 1.47))
        path.addCurve(to: pt(6.02, 0.79), control1: pt(5.87, 0.48), control2: pt(6.02, 0.65))
        path.addLine(to: pt(6.02, 2.28))
        path.addCurve(to: pt(3.33, 3.22), control1: pt(4.01, 1.91), control2: pt(3.49, 2.77))
        path.addCurve(to: pt(2.51, 4.35), control1: pt(3.24, 3.45), control2: pt(2.85, 4.16))
        path.addCurve(to: pt(2.5, 4.88), control1: pt(2.23, 4.2), control2: pt(1.83, 4.87))
        path.addCurve(to: pt(3.73, 4.06), control1: pt(3.13, 4.89), control2: pt(3.58, 4.3))
        path.addCurve(to: pt(6.06, 3.4), control1: pt(4.45, 2.85), control2: pt(5.6, 3.19))
        path.addCurve(to: pt(6.57, 4.47), control1: pt(6.13, 3.92), control2: pt(6.34, 4.27))
        path.addCurve(to: pt(2.93, 8.42), control1: pt(4.79, 4.27), control2: pt(2.93, 4.96))
        path.addCurve(to: pt(3.75, 10.57), control1: pt(2.93, 9.29), control2: pt(3.24, 10.01))
        path.addCurve(to: pt(3.83, 12.69), control1: pt(3.67, 10.77), control2: pt(3.39, 11.59))
        path.addCurve(to: pt(6.03, 11.87), control1: pt(3.83, 12.69), control2: pt(4.5, 12.9))
        path.addCurve(to: pt(8, 12.14), control1: pt(6.67, 12.05), control2: pt(7.35, 12.14))
        path.addCurve(to: pt(9.97, 11.87), control1: pt(8.65, 12.14), control2: pt(9.33, 12.05))
        path.addCurve(to: pt(12.17, 12.69), control1: pt(11.5, 12.9), control2: pt(12.17, 12.69))
        path.addCurve(to: pt(12.25, 10.57), control1: pt(12.61, 11.59), control2: pt(12.33, 10.77))
        path.addCurve(to: pt(13.07, 8.42), control1: pt(12.76, 10.01), control2: pt(13.07, 9.29))
        path.addCurve(to: pt(9.42, 4.47), control1: pt(13.07, 4.96), control2: pt(11.2, 4.27))
        path.addCurve(to: pt(9.96, 3.39), control1: pt(9.71, 4.22), control2: pt(9.96, 3.74))
        path.addLine(to: pt(9.96, 1.19))
        path.addCurve(to: pt(10.51, 0.41), control1: pt(9.96, 0.98), control2: pt(10.11, 0.73))
        path.addCurve(to: pt(16, 8), control1: pt(13.71, 1.47), control2: pt(16, 4.46))
        path.addCurve(to: pt(8, 16), control1: pt(16, 12.42), control2: pt(12.42, 16))
        path.closeSubpath()
        
        return path
    }
}
