import AppKit

/// The status item icon: a cardboard box whose lid opens while the menu bar panel is shown.
/// It is drawn in colour, so it is not a template image and is not tinted by macOS.
@MainActor
final class StatusBoxIcon {
    /// 0 is closed, 1 is fully open.
    private(set) var openness: CGFloat = 0
    private var timer: Timer?
    private let onChange: (NSImage) -> Void

    private static let duration: TimeInterval = 0.2

    init(onChange: @escaping (NSImage) -> Void) {
        self.onChange = onChange
    }

    var image: NSImage { Self.render(openness: openness) }

    func setOpen(_ open: Bool) {
        let target: CGFloat = open ? 1 : 0
        timer?.invalidate()
        timer = nil
        guard target != openness else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            openness = target
            onChange(image)
            return
        }
        let start = openness
        let began = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(Date().timeIntervalSince(began) / Self.duration, 1)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.openness = start + (target - start) * CGFloat(eased)
                self.onChange(self.image)
                if t >= 1 {
                    timer.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Drawing

    
    /// An isometric cube drawn as an outline, like the `shippingbox` symbol, with four triangular lid flaps
    /// that tilt outward as `openness` goes from 0 to 1.
    static func render(openness: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            let open = min(max(openness, 0), 1)
            let line = NSColor(srgbRed: 0.690, green: 0.478, blue: 0.227, alpha: 1)
            let side = NSColor(srgbRed: 0.784, green: 0.600, blue: 0.373, alpha: 0.55)
            let lid = NSColor(srgbRed: 0.851, green: 0.698, blue: 0.490, alpha: 0.95)
            let inside = NSColor(srgbRed: 0.416, green: 0.286, blue: 0.133, alpha: 0.9)
            let left = NSPoint(x: 3.5, y: 11)
            let front = NSPoint(x: 10, y: 8)
            let right = NSPoint(x: 16.5, y: 11)
            let back = NSPoint(x: 10, y: 14)
            let drop: CGFloat = 7
            func down(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x, y: p.y - drop) }
            
            func polygon(_ points: [NSPoint]) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.line(to: $0) }
                path.close()
                path.lineJoinStyle = .round
                path.lineWidth = 1.1
                return path
            }
            func fillAndStroke(_ path: NSBezierPath, fill: NSColor) {
                fill.setFill()
                path.fill()
                line.setStroke()
                path.stroke()
            }
            
            // Side faces.
            fillAndStroke(polygon([left, front, down(front), down(left)]), fill: side)
            fillAndStroke(polygon([front, right, down(right), down(front)]), fill: side)
            
            // Dark inside of the box, visible once the lid lifts.
            if open > 0 {
                inside.withAlphaComponent(open * 0.9).setFill()
                let hole = polygon([left, front, right, back])
                hole.fill()
            }
            
            /// A rectangular flap hinged on the edge a-b that covers half of the top face when closed (`across`
            /// is the half-width, parallel to the other edges). Open, it tilts away from the box along `lift`.
            func flap(_ a: NSPoint, _ b: NSPoint, across: NSPoint, lift: NSPoint) -> NSBezierPath {
                let angle = open * 100 * .pi / 180
                let d = NSPoint(
                    x: across.x * cos(angle) + lift.x * sin(angle),
                    y: across.y * cos(angle) + lift.y * sin(angle)
                )
                return polygon([a, b, NSPoint(x: b.x + d.x, y: b.y + d.y), NSPoint(x: a.x + d.x, y: a.y + d.y)])
            }
            // Two flaps on opposite long edges: the back-left one rises, the front-right one folds forward.
            fillAndStroke(flap(back, left, across: NSPoint(x: 3.25, y: -1.5), lift: NSPoint(x: -1.0, y: 4.0)), fill: lid)
            fillAndStroke(flap(front, right, across: NSPoint(x: -3.25, y: 1.5), lift: NSPoint(x: 1.8, y: -3.6)), fill: lid)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "DevKeeper"
        return image
    }
}
