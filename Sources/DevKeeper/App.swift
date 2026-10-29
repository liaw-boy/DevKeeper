import DevKeeperCore
import SwiftUI
import AppKit

@main
struct DevKeeperApp: App {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage(DKAppearance.storageKey) private var appearanceRaw = DKAppearance.system.rawValue
    private var appearance: DKAppearance { DKAppearance(rawValue: appearanceRaw) ?? .system }
    @State private var statusBarController: StatusBarController?
    
    init() {
        LegacyCleanup.run()
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            if ProcessInfo.processInfo.environment["DEVKEEPER_GALLERY"] == "1" {
                DesignGalleryView()
            } else {
                MainView()
                    .environmentObject(viewModel)
                    .preferredColorScheme(appearance.colorScheme)
                    .task {
                        // Development aid for screenshots: open on a given page (its Chinese title).
                        if let tab = ProcessInfo.processInfo.environment["DEVKEEPER_TAB"].flatMap(NavigationTab.init(rawValue:)) {
                            viewModel.selectedTab = tab
                        }
                        if statusBarController == nil {
                            statusBarController = StatusBarController(viewModel: viewModel)
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            // One main window only: every window would share the same view model and sheets.
            // (A single `Window` scene is not used because closing it would quit the app and the menu bar item.)
            CommandGroup(replacing: .newItem) {}
        }
    }
}
