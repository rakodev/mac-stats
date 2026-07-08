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
    private var globalClickMonitor: Any?
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
    @Published var temperatureUnit: TemperatureUnit = .celsius
    @Published var showSettings: Bool = false
    
    override init() {
        super.init()
        
        // Sync with preferences manager
        displayFormat = preferencesManager.displayFormat
        refreshInterval = RefreshInterval(rawValue: preferencesManager.refreshInterval) ?? .twoSeconds
        temperatureUnit = preferencesManager.temperatureUnit
        
        setupStatusItem()
        setupPopover()
        setupObservers()
        setupPreferencesObservers()
    }
    
    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        removeStatusItems()
    }
    
    private func setupStatusItem() {
        // Remove existing status item
        removeStatusItems()
        
        // Determine width based on layout style
        let width = statusItemWidth(for: preferencesManager.displayFormat)
        
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
        let newWidth = statusItemWidth(for: format)
        
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

    private func statusItemWidth(for format: DisplayFormat, metricCount: Int? = nil) -> CGFloat {
        let layoutStyle: StatusItemView.LayoutStyle = (format == .vertical) ? .vertical : .horizontal
        return StatusItemView.width(for: layoutStyle, metricCount: metricCount ?? enabledMetricCount())
    }

    private func enabledMetricCount() -> Int {
        let prefs = preferencesManager
        return visibleMetricFlags(prefs).filter { $0 }.count
    }

    private func visibleMetricFlags(_ prefs: UserPreferencesManager) -> [Bool] {
        [
            prefs.showCPU,
            prefs.showMemory,
            prefs.showDisk,
            prefs.showTemperature,
            prefs.showBattery,
            prefs.showThermalPressure,
            prefs.showMemoryPressure,
            prefs.showUptime
        ]
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
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let view = customView else { return }
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
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
        popover.contentSize = NSSize(width: 320, height: 420)
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

        preferencesManager.$temperatureUnit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newUnit in
                self?.temperatureUnit = newUnit
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
        
        Publishers.MergeMany(
            preferencesManager.$showCPU,
            preferencesManager.$showMemory,
            preferencesManager.$showDisk,
            preferencesManager.$showTemperature,
            preferencesManager.$showBattery,
            preferencesManager.$showThermalPressure,
            preferencesManager.$showMemoryPressure,
            preferencesManager.$showUptime
        )
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
        if prefs.showTemperature {
            metrics.append(StatusItemView.Metric(kind: .temp, celsius: stats.temperature?.celsius, unit: prefs.temperatureUnit))
        }
        if prefs.showBattery {
            let value = stats.battery.map { String(format: "%.0f%%", $0.percentage) } ?? "--%"
            metrics.append(StatusItemView.Metric(kind: .battery, text: value))
        }
        if prefs.showThermalPressure {
            metrics.append(StatusItemView.Metric(kind: .thermalPressure, text: stats.thermalPressure.shortValue))
        }
        if prefs.showMemoryPressure {
            metrics.append(StatusItemView.Metric(kind: .memoryPressure, text: stats.memoryPressure.shortValue))
        }
        if prefs.showUptime {
            metrics.append(StatusItemView.Metric(kind: .uptime, text: stats.uptime.shortValue))
        }
        
        // Update the custom view metrics and layout
        customView.metrics = metrics
        customView.layoutStyle = (prefs.displayFormat == .vertical) ? .vertical : .horizontal
        
        // Update width and frame if needed, but don't recreate the status item
        let expectedWidth = statusItemWidth(for: prefs.displayFormat, metricCount: metrics.count)
        
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

    fileprivate func canDisableVisibleMetric() -> Bool {
        enabledMetricCount() > 1
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
        VStack(alignment: .leading, spacing: 8) {
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("CPU")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f%%", systemMonitor.currentStats.cpuUsage))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                ProgressView(value: systemMonitor.currentStats.cpuUsage / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    .scaleEffect(y: 0.8)
            }
            .contentShape(Rectangle())
            .onTapGesture { MenuBarController.openActivityMonitorCPU() }
            .help("Click to open Activity Monitor CPU tab")
            .opacity(controller.preferencesManager.showCPU ? 1 : 0.25)

            // Memory Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: memoryIconName())
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Memory")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(systemMonitor.currentStats.memoryUsage.formattedUsed) / \(systemMonitor.currentStats.memoryUsage.formattedTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", systemMonitor.currentStats.memoryUsage.percentage))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                ProgressView(value: systemMonitor.currentStats.memoryUsage.percentage / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .scaleEffect(y: 0.8)
            }
            .contentShape(Rectangle())
            .onTapGesture { MenuBarController.openActivityMonitorMemory() }
            .help("Click to open Activity Monitor Memory tab")
            .opacity(controller.preferencesManager.showMemory ? 1 : 0.25)

            // Disk Usage
            VStack(alignment: .leading, spacing: 4) {
                let disk = systemMonitor.currentStats.diskUsage
                let pct = disk.percentage
                let color: Color = pct >= 90 ? .red : (pct >= 80 ? .orange : .blue)
                HStack {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                        .foregroundColor(color)
                    Text("Disk")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(disk.formattedUsed) / \(disk.formattedTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", pct))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
                ProgressView(value: pct / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .scaleEffect(y: 0.8)
            }
            .contentShape(Rectangle())
            .onTapGesture { MenuBarController.openActivityMonitorDisk() }
            .help("Click to open Activity Monitor Disk tab")
            .opacity(controller.preferencesManager.showDisk ? 1 : 0.25)

            // Temperature
            VStack(alignment: .leading, spacing: 4) {
                let temperature = systemMonitor.currentStats.temperature
                let celsius = temperature?.celsius
                let unit = controller.temperatureUnit
                let color: Color = {
                    guard let celsius else { return .secondary }
                    return celsius >= 90 ? .red : (celsius >= 80 ? .orange : .pink)
                }()
                HStack {
                    Image(systemName: "thermometer.medium")
                        .font(.caption)
                        .foregroundColor(color)
                    Text("Temperature")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if let temperature {
                        Text(temperature.sensorName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(temperature.formatted(unit: unit))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(color)
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
                ProgressView(value: min(max((celsius ?? 0) / 100.0, 0), 1))
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .scaleEffect(y: 0.8)
            }
            .help("CPU temperature from the first available AppleSMC CPU sensor")
            .opacity(controller.preferencesManager.showTemperature ? 1 : 0.25)

            // Battery
            HStack {
                let battery = systemMonitor.currentStats.battery
                let batteryColor: Color = {
                    guard let battery else { return .secondary }
                    if battery.percentage <= 10 && !battery.isPluggedIn { return .red }
                    if battery.percentage <= 25 && !battery.isPluggedIn { return .orange }
                    return .green
                }()
                Image(systemName: battery?.isCharging == true ? "battery.100.bolt" : "battery.100")
                    .font(.caption)
                    .foregroundColor(batteryColor)
                Text("Battery")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if let battery {
                    Text(battery.stateDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", battery.percentage))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(batteryColor)
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            .opacity(controller.preferencesManager.showBattery ? 1 : 0.25)

            // Thermal Pressure
            HStack {
                let thermalPressure = systemMonitor.currentStats.thermalPressure
                let color: Color = {
                    switch thermalPressure {
                    case .nominal: return .green
                    case .fair: return .yellow
                    case .serious: return .orange
                    case .critical: return .red
                    case .unknown: return .secondary
                    }
                }()
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption)
                    .foregroundColor(color)
                Text("Thermal Pressure")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(thermalPressure.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            .opacity(controller.preferencesManager.showThermalPressure ? 1 : 0.25)

            // Memory Pressure
            HStack {
                let memoryPressure = systemMonitor.currentStats.memoryPressure
                let color: Color = {
                    switch memoryPressure {
                    case .normal: return .green
                    case .warning: return .orange
                    case .critical: return .red
                    }
                }()
                Image(systemName: "memorychip")
                    .font(.caption)
                    .foregroundColor(color)
                Text("Memory Pressure")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(memoryPressure.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            .opacity(controller.preferencesManager.showMemoryPressure ? 1 : 0.25)

            // Uptime
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.indigo)
                Text("Uptime")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(systemMonitor.currentStats.uptime.formatted)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.indigo)
            }
            .opacity(controller.preferencesManager.showUptime ? 1 : 0.25)

            // Settings (collapsible)
            if controller.showSettings {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Format:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .leading)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text("Refresh:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .leading)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        Toggle("CPU", isOn: Binding(
                            get: { controller.preferencesManager.showCPU },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
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
                                if !newValue && !controller.canDisableVisibleMetric() {
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
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showDisk = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                        Toggle("Temp", isOn: Binding(
                            get: { controller.preferencesManager.showTemperature },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showTemperature = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                    }
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    HStack(spacing: 12) {
                        Toggle("Battery", isOn: Binding(
                            get: { controller.preferencesManager.showBattery },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showBattery = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                        Toggle("Thermal", isOn: Binding(
                            get: { controller.preferencesManager.showThermalPressure },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showThermalPressure = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                        Toggle("Mem Press", isOn: Binding(
                            get: { controller.preferencesManager.showMemoryPressure },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showMemoryPressure = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                    }
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    HStack(spacing: 12) {
                        Toggle("Uptime", isOn: Binding(
                            get: { controller.preferencesManager.showUptime },
                            set: { newValue in
                                let prefs = controller.preferencesManager
                                if !newValue && !controller.canDisableVisibleMetric() {
                                    controller.showLastMetricWarning(); return
                                }
                                prefs.showUptime = newValue
                                controller.updateStatusItemTitle()
                            }
                        ))
                    }
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    HStack {
                        Text("Temp Unit:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { controller.temperatureUnit },
                            set: { newUnit in
                                controller.temperatureUnit = newUnit
                                controller.preferencesManager.temperatureUnit = newUnit
                                controller.updateStatusItemTitle()
                            }
                        )) {
                            ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Toggle("Launch at login", isOn: Binding(
                        get: { controller.preferencesManager.launchAtLogin },
                        set: { controller.preferencesManager.launchAtLogin = $0 }
                    ))
                    .font(.caption)
                    .toggleStyle(.checkbox)
                }
            }
        }
        .padding(10)
        .frame(width: 280)
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