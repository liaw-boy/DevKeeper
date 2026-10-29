import AppKit
import SwiftUI

/// Hosts everything that floats above the window content: dropdown panels, tooltips and modal panels.
/// They are drawn by one root view so they are never clipped by scroll views or covered by siblings.
@MainActor
final class DKOverlayCenter: ObservableObject {
    struct Floating: Identifiable {
        let id = UUID()
        let owner: UUID?
        let anchor: CGRect
        let width: CGFloat?
        let content: AnyView
    }
    
    struct Tip: Equatable {
        let text: String
        let anchor: CGRect
    }
    
    @Published fileprivate(set) var panel: Floating?
    @Published fileprivate(set) var modal: AnyView?
    @Published fileprivate(set) var tip: Tip?
    
    /// `owner` lets a component close its own panel when it disappears.
    func showPanel<Content: View>(anchor: CGRect, width: CGFloat? = nil, owner: UUID? = nil, @ViewBuilder content: () -> Content) {
        tip = nil
        panel = Floating(owner: owner, anchor: anchor, width: width, content: AnyView(content()))
    }
    
    func dismissPanel() { panel = nil }
    
    func dismissPanel(owner: UUID) {
        if panel?.owner == owner { panel = nil }
    }
    
    func present<Content: View>(@ViewBuilder _ content: () -> Content) {
        panel = nil
        tip = nil
        modal = AnyView(content())
    }
    
    func dismissModal() { modal = nil }
    
    func showTip(_ text: String, anchor: CGRect) {
        guard panel == nil else { return }
        tip = Tip(text: text, anchor: anchor)
    }
    
    func hideTip(_ text: String) {
        if tip?.text == text { tip = nil }
    }
    
    /// Escape closes the topmost floating element. Returns true when it handled the key.
    fileprivate func handleEscape() -> Bool {
        if panel != nil { panel = nil; return true }
        if modal != nil { modal = nil; return true }
        return false
    }
}

enum DKCoordinateSpace {
    static let root = "dk-root"
}

private struct DKOverlayKey: EnvironmentKey {
    static let defaultValue: DKOverlayCenter? = nil
}

extension EnvironmentValues {
    /// Nil outside a `DKOverlayHost`; components then simply skip floating UI instead of crashing.
    var dkOverlay: DKOverlayCenter? {
        get { self[DKOverlayKey.self] }
        set { self[DKOverlayKey.self] = newValue }
    }
}

private struct DKAvailableHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 640
}

extension EnvironmentValues {
    /// Height of the window area the overlay host covers; modal panels stay within it.
    var dkAvailableHeight: CGFloat {
        get { self[DKAvailableHeightKey.self] }
        set { self[DKAvailableHeightKey.self] = newValue }
    }
}

/// Root container: put it around the whole window content once.
struct DKOverlayHost<Content: View>: View {
    @StateObject private var center = DKOverlayCenter()
    @State private var keyMonitor: Any?
    @State private var windowBox = DKWindowBox()
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                content
                    .frame(width: size.width, height: size.height)
                    // While a modal is open the window behind it must not take clicks, focus or shortcuts.
                    .disabled(center.modal != nil)
                
                if let modal = center.modal {
                    DK.scrim
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    modal
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }
                
                if let panel = center.panel {
                    Color.clear
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { center.dismissPanel() }
                    panel.content
                        .frame(width: panel.width)
                        .fixedSize(horizontal: panel.width == nil, vertical: true)
                        .dkFloatingSurface()
                        .alignmentGuide(.leading) { d in
                            -clamp(panel.anchor.minX, low: DK.Space.s, high: size.width - d.width - DK.Space.s)
                        }
                        .alignmentGuide(.top) { d in
                            let below = panel.anchor.maxY + DK.Space.xs
                            let y = below + d.height <= size.height - DK.Space.s ? below : panel.anchor.minY - DK.Space.xs - d.height
                            return -clamp(y, low: DK.Space.s, high: size.height - d.height - DK.Space.s)
                        }
                        .transition(.opacity)
                }
                
                if let tip = center.tip {
                    DKCappedWidth(maxWidth: 320) {
                        Text(tip.text)
                            .font(DK.Font.caption)
                            .foregroundColor(DK.textPrimary)
                            .lineLimit(4)
                    }
                    .padding(.horizontal, DK.Space.s)
                    .padding(.vertical, DK.Space.tight)
                    .dkFloatingSurface()
                    .alignmentGuide(.leading) { d in
                        -clamp(tip.anchor.midX - d.width / 2, low: DK.Space.s, high: size.width - d.width - DK.Space.s)
                    }
                    .alignmentGuide(.top) { d in
                        let below = tip.anchor.maxY + DK.Space.xs
                        let y = below + d.height <= size.height - DK.Space.s ? below : tip.anchor.minY - DK.Space.xs - d.height
                        return -clamp(y, low: DK.Space.s, high: size.height - d.height - DK.Space.s)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.dkOverlay, center)
            .environment(\.dkAvailableHeight, size.height)
            .coordinateSpace(name: DKCoordinateSpace.root)
            .animation(.easeOut(duration: 0.12), value: center.panel?.id)
            .animation(.easeOut(duration: 0.12), value: center.modal == nil)
        }
        .background(DKWindowReader(box: windowBox))
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }
    
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let center = center
        let box = windowBox
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only Escape pressed in this host's own window, and never while an input method is composing text.
            guard event.keyCode == 53, let window = box.window, event.window === window else { return event }
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            let handled = MainActor.assumeIsolated { center.handleEscape() }
            return handled ? nil : event
        }
    }
    
    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Weak reference to the window that contains an overlay host.
final class DKWindowBox {
    weak var window: NSWindow?
}

private struct DKWindowReader: NSViewRepresentable {
    let box: DKWindowBox
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in box.window = view?.window }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if box.window == nil {
            DispatchQueue.main.async { [weak nsView] in box.window = nsView?.window }
        }
    }
}

private func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
    max(low, min(value, max(low, high)))
}

/// Lays its content out at its natural width, but never wider than `maxWidth` (longer text wraps).
struct DKCappedWidth: Layout {
    let maxWidth: CGFloat
    
    init(maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(child.sizeThatFits(.unspecified).width, maxWidth)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension View {
    /// Surface for floating panels: the only place a shadow is used.
    func dkFloatingSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .fill(DK.surface)
                .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .stroke(DK.border, lineWidth: 1)
        )
    }
    
    /// Reports this view's frame in the root coordinate space.
    func dkTrackFrame(_ frame: Binding<CGRect>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { frame.wrappedValue = proxy.frame(in: .named(DKCoordinateSpace.root)) }
                    .onChange(of: proxy.frame(in: .named(DKCoordinateSpace.root))) { _, new in frame.wrappedValue = new }
            }
        )
    }
    
    /// Custom tooltip shown after a short hover delay. Passing nil shows nothing.
    func dkTooltip(_ text: String?) -> some View {
        modifier(DKTooltipModifier(text: text))
    }
}

private struct DKTooltipModifier: ViewModifier {
    let text: String?
    @Environment(\.dkOverlay) private var center
    @State private var frame: CGRect = .zero
    @State private var hoverTask: Task<Void, Never>?
    @State private var shownText: String?
    
    // Always applied (even when text is nil) so toggling the text does not rebuild the wrapped view.
    func body(content: Content) -> some View {
        content
            .dkTrackFrame($frame)
            .onHover { inside in
                hoverTask?.cancel()
                if inside, let text, !text.isEmpty {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        center?.showTip(text, anchor: frame)
                        shownText = text
                    }
                } else {
                    hide()
                }
            }
            .onChange(of: text) { _, _ in
                hoverTask?.cancel()
                hoverTask = nil
                hide()
            }
            .onDisappear {
                hoverTask?.cancel()
                hide()
            }
    }
    
    private func hide() {
        if let shownText { center?.hideTip(shownText) }
        shownText = nil
    }
}
