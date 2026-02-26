import SwiftUI
import ServiceManagement

@main
struct MacStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only app - need at least one scene but we'll hide it
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
        
        // Hide any existing windows
        NSApp.windows.forEach { window in
            window.close()
        }
        
        // Initialize menu bar controller
        menuBarController = MenuBarController()

        // Register login item on first launch if enabled
        if UserPreferencesManager.shared.launchAtLogin {
            DispatchQueue.global(qos: .utility).async {
                try? SMAppService.mainApp.register()
            }
        }
        
        // Prevent app from terminating when last window closes
        NSApp.delegate = self
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}