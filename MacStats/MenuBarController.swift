import Cocoa
import SwiftUI
import Combine

// MARK: - Display Format Enum
enum DisplayFormat: String, CaseIterable {
    case compact = "Compact"
    case detailed = "Detailed"
    case cpuOnly = "CPU Only"
    case memoryOnly = "Memory Only"
    
    var displayName: String {
        switch self {
        case .compact:
            return "Compact (CPU 7% MEM 43%)"
        case .detailed:
            return "Detailed (CPU 7.0% | MEM 27.4GB/64.0GB)"
        case .cpuOnly:
            return "CPU Only (CPU 7%)"
        case .memoryOnly:
            return "Memory Only (MEM 43%)"
        }
    }
    
    func formatStats(_ stats: SystemStats) -> String {
        switch self {
        case .compact:
            return String(format: "CPU %.0f%% MEM %.0f%%", 
                         stats.cpuUsage, 
                         stats.memoryUsage.percentage)
        case .detailed:
            return String(format: "CPU %.1f%% | MEM %.1fGB/%.1fGB", 
                         stats.cpuUsage,
                         stats.memoryUsage.usedGB,
                         stats.memoryUsage.totalGB)
        case .cpuOnly:
            return String(format: "CPU %.0f%%", stats.cpuUsage)
        case .memoryOnly:
            return String(format: "MEM %.0f%%", stats.memoryUsage.percentage)
        }
    }
}

// MARK: - Refresh Interval Enum
enum RefreshInterval: Double, CaseIterable {
    case oneSecond = 1.0
    case twoSeconds = 2.0
    case fiveSeconds = 5.0
    case tenSeconds = 10.0
    
    var displayName: String {
        switch self {
        case .oneSecond:
            return "1 second"
        case .twoSeconds:
            return "2 seconds"
        case .fiveSeconds:
            return "5 seconds"
        case .tenSeconds:
            return "10 seconds"
        }
    }
}

// MARK: - Menu Bar Controller
class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    var systemMonitor = SystemMonitor()
    public var preferencesManager = UserPreferencesManager.shared
    
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    // Published properties for SwiftUI binding
    @Published var displayFormat: DisplayFormat = .compact
    @Published var refreshInterval: RefreshInterval = .twoSeconds
    
    override init() {
        super.init()
        
        // Sync with preferences manager
        displayFormat = preferencesManager.displayFormat
        refreshInterval = RefreshInterval(rawValue: preferencesManager.refreshInterval) ?? .twoSeconds
        
        setupStatusItem()
        setupPopover()
        setupObservers()
        setupPreferencesObservers()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateStatusItemTitle()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                controller: self,
                systemMonitor: systemMonitor
            )
        )
    }
    
    private func setupObservers() {
        systemMonitor.$currentStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
    }
    
    private func setupPreferencesObservers() {
        // Only observe preferences manager changes, don't create bidirectional binding
        preferencesManager.$displayFormat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newFormat in
                self?.displayFormat = newFormat
            }
            .store(in: &cancellables)
        
        preferencesManager.$refreshInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterval in
                self?.refreshInterval = RefreshInterval(rawValue: newInterval) ?? .twoSeconds
                self?.systemMonitor.updateRefreshInterval(newInterval)
            }
            .store(in: &cancellables)
    }
    
    @objc private func statusItemClicked() {
        guard statusItem.button != nil else { return }
        
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Display Format submenu
        let formatMenu = NSMenu()
        for format in DisplayFormat.allCases {
            let item = NSMenuItem(title: format.rawValue, action: #selector(formatSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = format.hashValue
            item.state = format == displayFormat ? .on : .off
            formatMenu.addItem(item)
        }
        
        let formatMenuItem = NSMenuItem(title: "Display Format", action: nil, keyEquivalent: "")
        formatMenuItem.submenu = formatMenu
        menu.addItem(formatMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh interval submenu
        let refreshMenu = NSMenu()
        let intervals: [Double] = [1.0, 2.0, 5.0, 10.0]
        for interval in intervals {
            let item = NSMenuItem(title: "\(Int(interval))s", action: #selector(refreshIntervalSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(interval)
            item.state = interval == refreshInterval.rawValue ? .on : .off
            refreshMenu.addItem(item)
        }
        
        let refreshMenuItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        refreshMenuItem.submenu = refreshMenu
        menu.addItem(refreshMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func formatSelected(_ sender: NSMenuItem) {
        if let format = DisplayFormat.allCases.first(where: { $0.hashValue == sender.tag }) {
            displayFormat = format
            preferencesManager.displayFormat = format
            updateStatusItemTitle()
        }
    }
    
    @objc private func refreshIntervalSelected(_ sender: NSMenuItem) {
        let intervalValue = Double(sender.tag)
        refreshInterval = RefreshInterval(rawValue: intervalValue) ?? .twoSeconds
        preferencesManager.refreshInterval = refreshInterval.rawValue
        systemMonitor.updateRefreshInterval(refreshInterval.rawValue)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        
        let stats = systemMonitor.currentStats
        let title = displayFormat.formatStats(stats)
        
        button.title = title
    }
    
    // MARK: - Activity Monitor Integration
    static func openActivityMonitorCPU() {
        let script = """
        tell application "Activity Monitor"
            activate
            set view of front window to CPU
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
    
    static func openActivityMonitorMemory() {
        let script = """
        tell application "Activity Monitor"
            activate
            set view of front window to Memory
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
    
    // MARK: - Project Page
    static func openProjectPage() {
        guard let url = URL(string: "https://github.com/rakodev/mac-stats") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - SwiftUI Popover View
struct MenuBarPopoverView: View {
    @ObservedObject var controller: MenuBarController
    @ObservedObject var systemMonitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header
            LinkHeader()
            
            Divider()
            
            // CPU Usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.orange)
                    Text("CPU Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f%%", systemMonitor.currentStats.cpuUsage))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                ProgressView(value: systemMonitor.currentStats.cpuUsage / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                MenuBarController.openActivityMonitorCPU()
            }
            .help("Click to open Activity Monitor CPU tab")
            
            // Memory Usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundColor(.green)
                    Text("Memory Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f%%", systemMonitor.currentStats.memoryUsage.percentage))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                ProgressView(value: systemMonitor.currentStats.memoryUsage.percentage / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                
                HStack {
                    Text(systemMonitor.currentStats.memoryUsage.formattedUsed)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("of \(systemMonitor.currentStats.memoryUsage.formattedTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                MenuBarController.openActivityMonitorMemory()
            }
            .help("Click to open Activity Monitor Memory tab")
            
            Divider()
            
            // Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Display Format:")
                            .font(.caption)
                            .frame(width: 90, alignment: .leading)
                        
                        Picker("", selection: Binding(
                            get: { controller.displayFormat },
                            set: { newFormat in
                                controller.displayFormat = newFormat
                                controller.preferencesManager.displayFormat = newFormat
                            }
                        )) {
                            ForEach(DisplayFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 140)
                    }
                    
                    HStack {
                        Text("Refresh Rate:")
                            .font(.caption)
                            .frame(width: 90, alignment: .leading)
                        
                        Picker("", selection: Binding(
                            get: { controller.refreshInterval },
                            set: { newInterval in
                                controller.refreshInterval = newInterval
                                controller.preferencesManager.refreshInterval = newInterval.rawValue
                                controller.systemMonitor.updateRefreshInterval(newInterval.rawValue)
                            }
                        )) {
                            ForEach(RefreshInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 100)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Link Header View
private struct LinkHeader: View {
    @State private var hovering = false
    var body: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(.blue)
            Button(action: { MenuBarController.openProjectPage() }) {
                HStack(spacing: 4) {
                    Text("Mac Stats")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(hovering ? Color.blue.opacity(0.12) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Open project page on GitHub")
            Spacer()
        }
        .contentShape(Rectangle())
    }
}