import Foundation
import Combine
import Cocoa

// MARK: - User Preferences Manager
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()
    
    @Published var displayFormat: DisplayFormat {
        didSet {
            UserDefaults.standard.set(displayFormat.rawValue, forKey: "displayFormat")
        }
    }
    
    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }
    
    @Published var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            updateDockVisibility()
        }
    }
    
    // Visibility toggles for individual metrics
    @Published var showCPU: Bool {
        didSet { UserDefaults.standard.set(showCPU, forKey: "showCPU") }
    }
    @Published var showMemory: Bool {
        didSet { UserDefaults.standard.set(showMemory, forKey: "showMemory") }
    }
    @Published var showDisk: Bool {
        didSet { UserDefaults.standard.set(showDisk, forKey: "showDisk") }
    }
    
    private init() {
        // Load saved preferences or use defaults
        if let savedFormat = UserDefaults.standard.string(forKey: "displayFormat"),
           let format = DisplayFormat(rawValue: savedFormat) {
            self.displayFormat = format
        } else {
            // If legacy value (CPU Only / Memory Only) existed, fall back to compact
            self.displayFormat = .compact
            UserDefaults.standard.set(DisplayFormat.compact.rawValue, forKey: "displayFormat")
        }
        
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0
        
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        self.showCPU = UserDefaults.standard.object(forKey: "showCPU") as? Bool ?? true
        self.showMemory = UserDefaults.standard.object(forKey: "showMemory") as? Bool ?? true
        self.showDisk = UserDefaults.standard.object(forKey: "showDisk") as? Bool ?? true
    }
    
    private func updateLaunchAtLogin() {
        // Implementation for launch at login would go here
        // This requires additional setup with LoginItems or LaunchAgents
        print("Launch at login: \(launchAtLogin)")
    }
    
    private func updateDockVisibility() {
        DispatchQueue.main.async {
            if self.showInDock {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    func resetToDefaults() {
        displayFormat = .compact
        refreshInterval = 2.0
        launchAtLogin = false
        showInDock = false
        showCPU = true
        showMemory = true
        showDisk = true
    }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: Theme = .system
    
    private init() {
        if let savedTheme = UserDefaults.standard.string(forKey: "theme"),
           let theme = Theme(rawValue: savedTheme) {
            self.currentTheme = theme
        }
    }
    
    func setTheme(_ theme: Theme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        applyTheme()
    }
    
    private func applyTheme() {
        switch currentTheme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }
}

enum Theme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}