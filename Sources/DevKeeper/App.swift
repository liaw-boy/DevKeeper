import DevKeeperCore
import SwiftUI
import AppKit

@main
struct DevKeeperApp: App {
    @StateObject private var viewModel = AppViewModel()
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
                    .preferredColorScheme(.dark)
                    .task {
                        if statusBarController == nil {
                            statusBarController = StatusBarController(viewModel: viewModel)
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            SidebarCommands()
        }
    }
}
