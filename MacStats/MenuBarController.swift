import Cocoa
import SwiftUI
import Combine

// MARK: - Display Format Enum
enum DisplayFormat: String, CaseIterable {
    case compact = "Compact"
    case vertical = "Vertical"

    // Plain names (no preview text) per simplified UX
    var displayName: String { rawValue }
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
    private var statusItem: NSStatusItem?
    private var customView: StatusItemView?
    
    var systemMonitor = SystemMonitor()
    public var preferencesManager = UserPreferencesManager.shared
    
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    // Helper function to get memory icon name
    private func memoryIconName() -> String {
        if #available(macOS 11.0, *), NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil) != nil {
            return "sdcard"
        }
        return "memorychip" // fallback
    }
    
    // Published properties for SwiftUI binding
    @Published var displayFormat: DisplayFormat = .compact
    @Published var refreshInterval: RefreshInterval = .twoSeconds
    @Published var showSettings: Bool = true
    
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
    
    deinit {
        removeStatusItems()
    }
    
    private func setupStatusItem() {
        // Remove existing status item
        removeStatusItems()
        
        // Determine width based on layout style
        let width: CGFloat = {
            switch preferencesManager.displayFormat {
            case .vertical:
                return 90  // Narrower for vertical layout
            default:
                return 150 // Original width for compact horizontal layout
            }
        }()
        
        // Create the unified status item
        statusItem = NSStatusBar.system.statusItem(withLength: width)
        
        // Create custom view
        let custom = StatusItemView(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        
        // Set layout style based on display format
        custom.layoutStyle = (preferencesManager.displayFormat == .vertical) ? .vertical : .horizontal
        
        // Set up click handler
        custom.clickHandler = { [weak self] event in
            self?.handleStatusItemClick(event)
        }
        
        customView = custom
        statusItem?.view = custom
        
        // Update display with current metrics
        updateStatusItemDisplay()
    }
    
    private func updateStatusItemForFormat(_ format: DisplayFormat) {
        guard let statusItem = statusItem, let customView = customView else {
            print("MacStats: Status item or custom view is nil, recreating...")
            setupStatusItem()
            return
        }
        
        // Update width based on new format
        let newWidth: CGFloat = {
            switch format {
            case .vertical:
                return 90  // Narrower for vertical layout
            default:
                return 150 // Original width for compact horizontal layout
            }
        }()
        
        print("MacStats: Updating format to \(format), width: \(newWidth)")
        
        // Update the status item length first
        statusItem.length = newWidth
        
        // Update the frame
        customView.frame = NSRect(x: 0, y: 0, width: newWidth, height: 24)
        
        // Update the custom view's layout properties
        customView.layoutStyle = (format == .vertical) ? .vertical : .horizontal
        
        // Clear icon cache to ensure proper rendering with new layout
        customView.clearIconCache()
        
        // Force a redraw
        customView.needsDisplay = true
        
        print("MacStats: Successfully updated status item to format: \(format), width: \(newWidth)")
    }
    
    private func removeStatusItems() {
        statusItem = nil
        customView = nil
    }
    
    private func handleStatusItemClick(_ event: NSEvent) {
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let view = customView else { return }
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit MacStats", action: #selector(quitApp), keyEquivalent: "q")
        
        guard let view = customView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
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
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
        
        preferencesManager.$refreshInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterval in
                self?.refreshInterval = RefreshInterval(rawValue: newInterval) ?? .twoSeconds
                self?.systemMonitor.updateRefreshInterval(newInterval)
            }
            .store(in: &cancellables)
        
        preferencesManager.$showCPU
            .merge(with: preferencesManager.$showMemory, preferencesManager.$showDisk)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupStatusItem() // Recreate status items when visibility changes
            }
            .store(in: &cancellables)
    }
    
    @objc private func formatSelected(_ sender: NSMenuItem) {
        if let format = DisplayFormat.allCases.first(where: { $0.hashValue == sender.tag }) {
            print("MacStats: Switching to format: \(format)")
            displayFormat = format
            preferencesManager.displayFormat = format
            
            // Update the existing status item instead of recreating it
            updateStatusItemForFormat(format)
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
    
    func updateStatusItemTitle() { 
        updateStatusItemDisplay() 
    }
    
    private func updateStatusItemDisplay() {
        guard let customView = customView else { return }
        
        let stats = systemMonitor.currentStats
        let prefs = preferencesManager
        
        var metrics: [StatusItemView.Metric] = []
        
        // Build metrics array based on enabled metrics
        if prefs.showCPU {
            metrics.append(StatusItemView.Metric(kind: .cpu, percentage: stats.cpuUsage))
        }
        if prefs.showMemory {
            metrics.append(StatusItemView.Metric(kind: .mem, percentage: stats.memoryUsage.percentage))
        }
        if prefs.showDisk {
            metrics.append(StatusItemView.Metric(kind: .disk, percentage: stats.diskUsage.percentage))
        }
        
        // Update the custom view metrics and layout
        customView.metrics = metrics
        customView.layoutStyle = (prefs.displayFormat == .vertical) ? .vertical : .horizontal
        
        // Update width and frame if needed, but don't recreate the status item
        let expectedWidth: CGFloat = {
            switch prefs.displayFormat {
            case .vertical:
                return 90  // Narrower for vertical layout
            default:
                return 150 // Original width for compact horizontal layout
            }
        }()
        
        // Update status item length and custom view frame
        statusItem?.length = expectedWidth
        customView.frame = NSRect(x: 0, y: 0, width: expectedWidth, height: 24)
        
        // Force redraw
        customView.needsDisplay = true
    }
    
    @objc private func showSettingsWindow() {
        // Implementation for showing settings window would go here
        // For now, just show a placeholder alert
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Settings window not yet implemented"
        alert.alertStyle = .informational
        alert.runModal()
    }

    // Provide minimal user feedback when an action is disallowed (e.g., hiding last metric)
    // fileprivate so SwiftUI view structs in this file can invoke it.
    fileprivate func showLastMetricWarning() {
        // Simple, lightweight alert. Could be replaced with subtle HUD later.
        let alert = NSAlert()
        alert.messageText = "At least one metric must remain visible"
        alert.alertStyle = .informational
        // Run asynchronously so it doesn't block UI update pipeline.
        DispatchQueue.main.async {
            alert.runModal()
        }
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
    
    static func openActivityMonitorDisk() {
        let script = """
        tell application "Activity Monitor"
            activate
            set view of front window to Disk
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
    
    private func memoryIconName() -> String {
        if #available(macOS 11.0, *), NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil) != nil {
            return "sdcard"
        }
        return "memorychip" // fallback
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with settings toggle
            HStack(alignment: .center) {
                LinkHeader()
                Spacer()
                Button(action: { withAnimation { controller.showSettings.toggle() } }) {
                    Image(systemName: controller.showSettings ? "gearshape.fill" : "gearshape")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle settings visibility")
            }
            
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
            .onTapGesture { MenuBarController.openActivityMonitorCPU() }
            .help("Click to open Activity Monitor CPU tab")
            .opacity(controller.preferencesManager.showCPU ? 1 : 0.25)
            .overlay(Group { if !controller.preferencesManager.showCPU { Text("Hidden").font(.caption2).foregroundColor(.secondary) } })
            
            // Memory Usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: memoryIconName())
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
            .onTapGesture { MenuBarController.openActivityMonitorMemory() }
            .help("Click to open Activity Monitor Memory tab")
            .opacity(controller.preferencesManager.showMemory ? 1 : 0.25)
            .overlay(Group { if !controller.preferencesManager.showMemory { Text("Hidden").font(.caption2).foregroundColor(.secondary) } })
            
            Divider()
            
            // Disk Usage
            VStack(alignment: .leading, spacing: 8) {
                let disk = systemMonitor.currentStats.diskUsage
                let pct = disk.percentage
                let color: Color = pct >= 90 ? .red : (pct >= 80 ? .orange : .blue)
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(color)
                    Text("Disk Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f%%", pct))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
                ProgressView(value: pct / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                HStack {
                    Text(disk.formattedUsed)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("of \(disk.formattedTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { MenuBarController.openActivityMonitorDisk() }
            .help("Click to open Activity Monitor Disk tab")
            .opacity(controller.preferencesManager.showDisk ? 1 : 0.25)
            .overlay(Group { if !controller.preferencesManager.showDisk { Text("Hidden").font(.caption2).foregroundColor(.secondary) } })
            
            // Settings (collapsible)
            if controller.showSettings {
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
                                    controller.updateStatusItemTitle()
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
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visible Metrics:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Toggle("CPU", isOn: Binding(
                                get: { controller.preferencesManager.showCPU },
                                set: { newValue in
                                    let prefs = controller.preferencesManager
                                    if !newValue && !prefs.showMemory && !prefs.showDisk {
                                        controller.showLastMetricWarning(); return
                                    }
                                    prefs.showCPU = newValue
                                    controller.updateStatusItemTitle()
                                }
                            ))
                            Toggle("Memory", isOn: Binding(
                                get: { controller.preferencesManager.showMemory },
                                set: { newValue in
                                    let prefs = controller.preferencesManager
                                    if !newValue && !prefs.showCPU && !prefs.showDisk {
                                        controller.showLastMetricWarning(); return
                                    }
                                    prefs.showMemory = newValue
                                    controller.updateStatusItemTitle()
                                }
                            ))
                            Toggle("Disk", isOn: Binding(
                                get: { controller.preferencesManager.showDisk },
                                set: { newValue in
                                    let prefs = controller.preferencesManager
                                    if !newValue && !prefs.showCPU && !prefs.showMemory {
                                        controller.showLastMetricWarning(); return
                                    }
                                    prefs.showDisk = newValue
                                    controller.updateStatusItemTitle()
                                }
                            ))
                        }
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