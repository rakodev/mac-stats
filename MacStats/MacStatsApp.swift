import SwiftUI

@main
struct MacStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize menu bar controller
        menuBarController = MenuBarController()
        
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