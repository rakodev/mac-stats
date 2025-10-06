import Cocoa
import SwiftUI
import Combine

// MARK: - Display Format Enum
enum DisplayFormat: String, CaseIterable {
    case compact = "Compact"
    case detailed = "Detailed"

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
    private var cpuStatusItem: NSStatusItem?
    private var memoryStatusItem: NSStatusItem?
    private var diskStatusItem: NSStatusItem?
    
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
        // Remove existing status items
        removeStatusItems()
        
        let prefs = preferencesManager
        
        // Create status items in reverse order since macOS displays them right-to-left
        // This ensures left-to-right order: CPU, Memory, Disk
        
        // Calculate fixed width to accommodate icon + "100%" text
    // Reduced from 65 -> 58 to tighten horizontal spacing between items
    // Still sufficient for icon + "100%" (monospaced digits) without clipping
    let fixedWidth: CGFloat = 58
        
        // Create Disk status item (rightmost)
        if prefs.showDisk {
            diskStatusItem = NSStatusBar.system.statusItem(withLength: fixedWidth)
            if let button = diskStatusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.isEnabled = true
                button.alignment = .left
            }
        }
        
        // Create Memory status item (middle)
        if prefs.showMemory {
            memoryStatusItem = NSStatusBar.system.statusItem(withLength: fixedWidth)
            if let button = memoryStatusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.isEnabled = true
                button.alignment = .left
            }
        }
        
        // Create CPU status item (leftmost)
        if prefs.showCPU {
            cpuStatusItem = NSStatusBar.system.statusItem(withLength: fixedWidth)
            if let button = cpuStatusItem?.button {
                button.action = #selector(statusItemClicked)
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.isEnabled = true
                button.alignment = .left
            }
        }
        
        // Update all displays
        updateStatusItemDisplay()
    }
    
    private func removeStatusItems() {
        if let item = cpuStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            cpuStatusItem = nil
        }
        if let item = memoryStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            memoryStatusItem = nil
        }
        if let item = diskStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            diskStatusItem = nil
        }
    }
    
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        
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
        // Determine which status item button to show the popover from
        // Prefer CPU, then Memory, then Disk
        var targetButton: NSStatusBarButton?
        
        if let cpuButton = cpuStatusItem?.button {
            targetButton = cpuButton
        } else if let memoryButton = memoryStatusItem?.button {
            targetButton = memoryButton
        } else if let diskButton = diskStatusItem?.button {
            targetButton = diskButton
        }
        
        guard let button = targetButton else { return }
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
        
        // Show the menu using any available status item
        var targetStatusItem: NSStatusItem?
        if let cpu = cpuStatusItem {
            targetStatusItem = cpu
        } else if let memory = memoryStatusItem {
            targetStatusItem = memory
        } else if let disk = diskStatusItem {
            targetStatusItem = disk
        }
        
        if let statusItem = targetStatusItem {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
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
    
    func updateStatusItemTitle() { 
        updateStatusItemDisplay() 
    }
    
    private func updateStatusItemDisplay() {
        let stats = systemMonitor.currentStats
        let prefs = preferencesManager
        
        // Update CPU status item
        if prefs.showCPU, let button = cpuStatusItem?.button {
            updateStatusButton(button, 
                             iconName: "cpu", 
                             value: stats.cpuUsage, 
                             format: "%.0f%%")
        }
        
        // Update Memory status item
        if prefs.showMemory, let button = memoryStatusItem?.button {
            updateStatusButton(button, 
                             iconName: memoryIconName(), 
                             value: stats.memoryUsage.percentage, 
                             format: "%.0f%%")
        }
        
        // Update Disk status item
        if prefs.showDisk, let button = diskStatusItem?.button {
            updateStatusButton(button, 
                             iconName: "internaldrive", 
                             value: stats.diskUsage.percentage, 
                             format: "%.0f%%")
        }
    }
    
    private func updateStatusButton(_ button: NSStatusBarButton, iconName: String, value: Double, format: String) {
        // Set icon (SF Symbol with template behavior)
        if #available(macOS 11.0, *), let systemImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let configuredImage = systemImage.withSymbolConfiguration(config) ?? systemImage
            configuredImage.isTemplate = true // Ensure template behavior
            button.image = configuredImage
        } else {
            // Fallback for older macOS
            button.image = nil
        }
        
        // Create fixed-width percentage text using explicit width without relying on trimmed leading spaces.
        // Use FIGURE SPACE (U+2007) for padding – it has digit width in most fonts and is not trimmed by AppKit.
        let percentage = Int(value.rounded())
        let numberString = String(percentage)
        let padCount = max(0, 3 - numberString.count)
        let figureSpace = "\u{2007}" // figure space
        let paddedNumber = String(repeating: figureSpace, count: padCount) + numberString
        let formattedText = paddedNumber + "%" // Always 4 glyphs wide (3 digits/pads + %)

        // Build attributed string with left alignment to stop centering shifts inside fixed-length button
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        button.attributedTitle = NSAttributedString(string: formattedText, attributes: attributes)
        button.font = font
        
        // Ensure image sits at the very left and text follows without re-centering
        button.imagePosition = .imageLeading
        if let cell = button.cell as? NSButtonCell {
            cell.alignment = .left
            cell.imagePosition = .imageLeading
        }
        
        // Set tooltip
        let metricName = iconName == "cpu" ? "CPU" : (iconName == "sdcard" || iconName == "memorychip" ? "Memory" : "Disk")
        let tooltipPercentage = String(format: "%.1f%%", value)
        button.toolTip = "\(metricName): \(tooltipPercentage)"
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