import AppKit
import CoreGraphics
import Foundation

let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        return nil
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // Standard macOS squircle
    let pad = s * 0.095
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let corner = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.02),
        blur: s * 0.05,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )
    
    // Background gradient
    ctx.addPath(squircle)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.restoreGState()

    // Inner subtle border
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(s * 0.008)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.strokePath()
    ctx.restoreGState()

    // Draw central Package symbol (Isometric cube in clean Apple HIG style)
    let cx = s * 0.5
    let cy = s * 0.5
    let cubeSize = s * 0.24

    ctx.saveGState()
    ctx.setLineWidth(s * 0.03)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(red: 0.9, green: 0.92, blue: 0.96, alpha: 0.95))

    // Top face
    let pTop = CGPoint(x: cx, y: cy + cubeSize * 0.9)
    let pLeft = CGPoint(x: cx - cubeSize * 0.9, y: cy + cubeSize * 0.4)
    let pRight = CGPoint(x: cx + cubeSize * 0.9, y: cy + cubeSize * 0.4)
    let pCenter = CGPoint(x: cx, y: cy - cubeSize * 0.1)
    let pBottom = CGPoint(x: cx, y: cy - cubeSize * 1.0)
    let pBottomLeft = CGPoint(x: cx - cubeSize * 0.9, y: cy - cubeSize * 0.5)
    let pBottomRight = CGPoint(x: cx + cubeSize * 0.9, y: cy - cubeSize * 0.5)

    // Outer contour
    let path = CGMutablePath()
    path.move(to: pTop)
    path.addLine(to: pRight)
    path.addLine(to: pBottomRight)
    path.addLine(to: pBottom)
    path.addLine(to: pBottomLeft)
    path.addLine(to: pLeft)
    path.closeSubpath()
    ctx.addPath(path)
    ctx.strokePath()

    // Inner edges
    let innerPath = CGMutablePath()
    innerPath.move(to: pCenter)
    innerPath.addLine(to: pTop)
    innerPath.move(to: pCenter)
    innerPath.addLine(to: pBottomLeft)
    innerPath.move(to: pCenter)
    innerPath.addLine(to: pBottomRight)
    ctx.addPath(innerPath)
    ctx.strokePath()

    ctx.restoreGState()

    return rep.representation(using: .png, properties: [:])
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for sz in sizes {
    if let data = renderIcon(pixelSize: sz) {
        let filename: String
        if sz == 16 { filename = "icon_16x16.png" }
        else if sz == 32 { filename = "icon_16x16@2x.png" }
        else if sz == 64 { filename = "icon_32x32@2x.png" }
        else if sz == 128 { filename = "icon_128x128.png" }
        else if sz == 256 { filename = "icon_128x128@2x.png" }
        else if sz == 512 { filename = "icon_256x256@2x.png" }
        else { filename = "icon_512x512@2x.png" }
        
        let path = (iconsetPath as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
