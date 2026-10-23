import AppKit
import SwiftUI
import Combine

extension UserDefaults {
    /// KVO-compatible accessor; the property name must match `StatusBarController.showStatusItemKey`.
    @objc dynamic var showStatusBarItem: Bool {
        object(forKey: "showStatusBarItem") as? Bool ?? true
    }
}

@MainActor
public final class StatusBarController: NSObject {
    public static var shared: StatusBarController?
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel: AppViewModel
    private var cancellables = Set<AnyCancellable>()
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        super.init()
        
        setupStatusItem()
        setupPopover()
        observeViewModel()
        observeVisibilitySetting()
        
        StatusBarController.shared = self
    }
    
    /// UserDefaults key toggled from the Settings page.
    public static let showStatusItemKey = "showStatusBarItem"
    
    private func observeVisibilitySetting() {
        applyVisibility()
        UserDefaults.standard.publisher(for: \.showStatusBarItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
    }
    
    private func applyVisibility() {
        let defaults = UserDefaults.standard
        let show = defaults.object(forKey: Self.showStatusItemKey) as? Bool ?? true
        guard statusItem.isVisible != show else { return }
        if !show { closePopover() }
        statusItem.isVisible = show
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            updateBadge()
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        
        popover.contentViewController = makeHostingController()
    }
    
    private func makeHostingController() -> NSHostingController<MenuBarView> {
        let hosting = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
        hosting.sizingOptions = .preferredContentSize
        return hosting
    }
    
    private func observeViewModel() {
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateBadge()
                }
            }
            .store(in: &cancellables)
    }
    
    public func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = viewModel.totalOutdatedCount
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = createMergedBadgeImage(count: count)
    }
    
    private func createMergedBadgeImage(count: Int) -> NSImage {
        let iconSize: CGFloat = 17.0
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
        guard let baseIcon = NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "DevKeeper")?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        
        if count == 0 {
            baseIcon.isTemplate = true
            return baseIcon
        }
        
        let text = "\(count)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        
        let badgeH: CGFloat = 13.0
        let badgeW = max(badgeH, textSize.width + 6.0)
        
        // Canvas width: base icon + offset overlapping badge
        let overlapOffset: CGFloat = 9.5
        let canvasW = overlapOffset + badgeW
        let canvasH: CGFloat = 20.0
        
        let img = NSImage(size: NSSize(width: canvasW, height: canvasH), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            // 1. Draw pure bright white cube icon
            let iconY: CGFloat = 1.5
            let iconRect = NSRect(x: 0, y: iconY, width: iconSize, height: iconSize)
            baseIcon.draw(in: iconRect)
            
            // 2. Badge position (top-right overlapping the cube)
            let badgeY: CGFloat = 7.0
            let badgeRect = NSRect(x: overlapOffset, y: badgeY, width: badgeW, height: badgeH)
            
            // Transparent cut-out mask around badge to cleanly carve into the cube
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            let cutoutRect = badgeRect.insetBy(dx: -1.5, dy: -1.5)
            let cutoutPath = CGPath(roundedRect: cutoutRect, cornerWidth: cutoutRect.height / 2, cornerHeight: cutoutRect.height / 2, transform: nil)
            ctx.addPath(cutoutPath)
            ctx.fillPath()
            ctx.restoreGState()
            
            // 3. Draw badge capsule in vibrant orange (#ea6f47)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
            NSColor(red: 0.918, green: 0.435, blue: 0.278, alpha: 1.0).setFill()
            badgePath.fill()
            
            // 4. Draw number text mathematically centered down to the exact pixel (top=3px, bottom=3px, left=4px, right=4px)
            let textX = badgeRect.origin.x + (badgeW - textSize.width) / 2
            let textY = badgeRect.midY - font.capHeight / 2 + font.descender - 0.75
            (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)
            
            return true
        }
        
        img.isTemplate = false
        return img
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updateBadge()
            // Always refresh hosting controller with current state
            popover.contentViewController = makeHostingController()
            
            // Show centered directly beneath the status item button
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    public func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}
