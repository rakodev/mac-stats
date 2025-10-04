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

// MARK: - Symbol Builder (CPU / Memory / Disk)
private enum SymbolBuilder {
    static let cpuPlaceholder = "[CPU]"
    static let memPlaceholder = "[MEM]"
    static let diskPlaceholder = "[DISK]"
    
    private static func symbolName(for placeholder: String) -> String? {
        switch placeholder {
        case cpuPlaceholder: return "cpu"
        case memPlaceholder:
            // Prefer sdcard (micro SD style) if available, fallback to memorychip
            if #available(macOS 11.0, *), NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil) != nil {
                return "sdcard"
            }
            return "memorychip"
        case diskPlaceholder: return "internaldrive"
        default: return nil
        }
    }
    
    static func attributedSymbol(for placeholder: String, font: NSFont) -> NSAttributedString? {
        guard #available(macOS 11.0, *), let name = symbolName(for: placeholder),
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        // Scale symbol larger than text cap height for better legibility in the menubar.
        // Requested: make icons roughly 2x larger than previous implementation.
        let scaleMultiplier: CGFloat = 2.0
        let targetHeight = font.capHeight * scaleMultiplier
        let ratio = image.size.height > 0 ? targetHeight / image.size.height : 1
        let scaledSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let resized = NSImage(size: scaledSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaledSize))
        resized.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = resized
        // Nudge vertically so the larger glyph sits more naturally on the baseline.
        attachment.bounds = NSRect(x: 0, y: font.descender + 1, width: scaledSize.width, height: scaledSize.height)
        return NSAttributedString(attachment: attachment)
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
                self?.updateStatusItemTitle()
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
    
    func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        
        let stats = systemMonitor.currentStats
        let raw = buildDynamicTitle(stats: stats)
        let placeholders = [SymbolBuilder.cpuPlaceholder, SymbolBuilder.memPlaceholder, SymbolBuilder.diskPlaceholder]
        if placeholders.contains(where: { raw.contains($0) }) {
            let font = button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            let result = NSMutableAttributedString()
            var cursor = raw.startIndex
            while cursor < raw.endIndex {
                // Find next placeholder occurrence among all
                var nextRange: Range<String.Index>? = nil
                var matchedPlaceholder: String? = nil
                for ph in placeholders {
                    if let r = raw.range(of: ph, range: cursor..<raw.endIndex), (nextRange == nil || r.lowerBound < nextRange!.lowerBound) {
                        nextRange = r
                        matchedPlaceholder = ph
                    }
                }
                if let r = nextRange, let ph = matchedPlaceholder {
                    // Append preceding text
                    if r.lowerBound > cursor {
                        let text = String(raw[cursor..<r.lowerBound])
                        result.append(NSAttributedString(string: text, attributes: [.font: font]))
                    }
                    // Append symbol (or fallback text)
                    if let symbol = SymbolBuilder.attributedSymbol(for: ph, font: font) {
                        // Append with tight binding to following number: symbol + thin space (U+2009)
                        if result.length > 0, !result.string.hasSuffix(" ") { result.append(NSAttributedString(string: " ")) }
                        result.append(symbol)
                        // thin space to visually bind the value to this icon without a wide gap
                        result.append(NSAttributedString(string: "\u{2009}"))
                    } else {
                        // Fallback textual label (short)
                        if result.length > 0, !result.string.hasSuffix(" ") { result.append(NSAttributedString(string: " ")) }
                        let fallback: String
                        switch ph {
                        case SymbolBuilder.cpuPlaceholder: fallback = "CPU "
                        case SymbolBuilder.memPlaceholder: fallback = "MEM "
                        case SymbolBuilder.diskPlaceholder: fallback = "DISK "
                        default: fallback = ""
                        }
                        result.append(NSAttributedString(string: fallback, attributes: [.font: font]))
                    }
                    cursor = r.upperBound
                } else {
                    // No more placeholders
                    let text = String(raw[cursor..<raw.endIndex])
                    result.append(NSAttributedString(string: text, attributes: [.font: font]))
                    break
                }
            }
            button.attributedTitle = result
        } else {
            button.attributedTitle = NSAttributedString(string: raw)
        }
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
    
    private func buildDynamicTitle(stats: SystemStats) -> String {
        let prefs = preferencesManager
        switch displayFormat {
        case .compact:
            var parts: [String] = []
            if prefs.showCPU { parts.append(String(format: "[CPU]%.0f%%", stats.cpuUsage)) }
            if prefs.showMemory { parts.append(String(format: "[MEM]%.0f%%", stats.memoryUsage.percentage)) }
            if prefs.showDisk { parts.append(String(format: "[DISK]%.0f%%", stats.diskUsage.percentage)) }
            return parts.joined(separator: " ")
        case .detailed:
            var segments: [String] = []
            if prefs.showCPU { segments.append(String(format: "[CPU]%.1f%%", stats.cpuUsage)) }
            if prefs.showMemory { segments.append(String(format: "[MEM]%.1fGB/%.1fGB", stats.memoryUsage.usedGB, stats.memoryUsage.totalGB)) }
            if prefs.showDisk { segments.append(String(format: "[DISK]%.1fGB/%.1fGB", stats.diskUsage.usedGB, stats.diskUsage.totalGB)) }
            return segments.joined(separator: " | ")
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