import DevKeeperCore
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
    private let viewModel: AppViewModel
    private var cancellables = Set<AnyCancellable>()
    private var panel: MenuBarPanel?
    private var outsideClickMonitor: Any?
    private var ownClickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var lastBadgeCount = -1
    private var boxIcon: StatusBoxIcon!
    /// When the panel last closed because it lost focus; clicking the status item at that moment must not reopen it.
    private var lastAutoClose = Date.distantPast
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        super.init()
        
        setupStatusItem()
        observeViewModel()
        observeVisibilitySetting()
        
        StatusBarController.shared = self
        
        // Development aid for screenshots: open the panel without clicking the status item.
        if ProcessInfo.processInfo.environment["DEVKEEPER_SHOW_MENU_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.showPanel(autoDismiss: false) }
        }
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
        let show = UserDefaults.standard.object(forKey: Self.showStatusItemKey) as? Bool ?? true
        guard statusItem.isVisible != show else { return }
        if !show { closePanel() }
        statusItem.isVisible = show
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        // A coloured cardboard box rather than a template image; its lid opens while the panel is shown.
        boxIcon = StatusBoxIcon { [weak button] image in button?.image = image }
        button.image = boxIcon.image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp])
        updateBadge()
    }
    
    private func observeViewModel() {
        // Log output streams in many small changes; only redraw once things settle and the count changed.
        viewModel.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
    }
    
    public func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = viewModel.totalOutdatedCount
        guard count != lastBadgeCount else { return }
        lastBadgeCount = count
        button.title = count > 0 ? "\(count)" : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.setAccessibilityLabel(count > 0 ? "DevKeeper，\(count) 項可升級" : "DevKeeper")
    }
    
    // MARK: - Panel
    
    @objc private func togglePanel(_ sender: AnyObject?) {
        if panel != nil {
            closePanel()
        } else if Date().timeIntervalSince(lastAutoClose) > 0.3 {
            showPanel()
        }
    }
    
    private func showPanel(autoDismiss: Bool = true) {
        guard panel == nil else { return }
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let hosting = NSHostingView(rootView: MenuBarView(viewModel: viewModel) { [weak self] in self?.closePanel() })
        let size = hosting.fittingSize
        let panel = MenuBarPanel(size: size)
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.closePanel() }
        // Follows the main window, which is dark until the appearance setting lands.
        panel.appearance = NSAppearance(named: .darkAqua)
        
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(buttonRect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonRect.minY - 6))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        boxIcon.setOpen(true)
        guard autoDismiss else { return }
        
        // Close on clicks elsewhere. Losing key status is not used: the panel does not activate the app,
        // so it can resign key right after opening.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoClose() }
        }
        let statusWindow = buttonWindow
        ownClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            // Clicks on the status item are handled by togglePanel.
            if event.window !== panel && event.window !== statusWindow {
                MainActor.assumeIsolated { self?.autoClose() }
            }
            return event
        }
        // Switching apps with Cmd-Tab involves no click.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.autoClose() }
        }
    }
    
    private func autoClose() {
        guard panel != nil else { return }
        lastAutoClose = Date()
        closePanel()
    }
    
    public func closePanel() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let ownClickMonitor { NSEvent.removeMonitor(ownClickMonitor) }
        ownClickMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        guard let closing = panel else { return }
        boxIcon.setOpen(false)
        closing.orderOut(nil)
        panel = nil
        // Keep the window alive until the click that closed it has finished dispatching.
        DispatchQueue.main.async { _ = closing }
    }
}

/// Borderless panel under the status item; draws its own rounded surface.
final class MenuBarPanel: NSPanel {
    var onCancel: () -> Void = {}
    
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
    
    override var canBecomeKey: Bool { true }
    
    /// Escape.
    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
