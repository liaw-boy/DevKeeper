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
    ), let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }
    let ctx = nsContext.cgContext

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
        // The app's accent blue (DK.accent, light variant) with a slightly lighter top-left.
        CGColor(red: 0.357, green: 0.529, blue: 0.941, alpha: 1.0),
        CGColor(red: 0.231, green: 0.435, blue: 0.847, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }
    ctx.restoreGState()

    // Inner subtle border
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(s * 0.008)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.strokePath()
    ctx.restoreGState()

    // The same box symbol the sidebar brand uses.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()

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
