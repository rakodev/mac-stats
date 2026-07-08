import Cocoa

// Fixed pixel slot layout to prevent jitter while metrics update
final class StatusItemView: NSView {
    struct Metric {
        enum Kind { case cpu, mem, disk, temp }
        enum ValueStyle { case percentage, temperature(TemperatureUnit) }

        let kind: Kind
        let value: Double?
        let valueStyle: ValueStyle

        init(kind: Kind, percentage: Double) {
            self.kind = kind
            self.value = percentage
            self.valueStyle = .percentage
        }

        init(kind: Kind, celsius: Double?, unit: TemperatureUnit) {
            self.kind = kind
            switch unit {
            case .celsius:
                self.value = celsius
            case .fahrenheit:
                self.value = celsius.map { ($0 * 9.0 / 5.0) + 32.0 }
            }
            self.valueStyle = .temperature(unit)
        }

        func formattedValue(horizontal: Bool) -> String {
            switch valueStyle {
            case .percentage:
                guard let value else { return horizontal ? " --%" : "--%" }
                let rounded = Int(round(max(0, min(100, value))))
                return horizontal ? String(format: "%3d%%", rounded) : String(format: "%2d%%", rounded)
            case .temperature(let unit):
                guard let value else { return "--\(unit.symbol)" }
                let rounded = Int(round(value))
                return horizontal ? String(format: "%3d%@", rounded, unit.symbol) : String(format: "%2d%@", rounded, unit.symbol)
            }
        }
    }

    enum LayoutStyle {
        case horizontal
        case vertical
    }

    var metrics: [Metric] = [] { didSet { needsDisplay = true } }
    var layoutStyle: LayoutStyle = .horizontal { didSet { needsDisplay = true } }
    var clickHandler: ((NSEvent) -> Void)?

    private var iconCache: [Metric.Kind: NSImage] = [:]

    static func width(for layoutStyle: LayoutStyle, metricCount: Int) -> CGFloat {
        let count = max(1, metricCount)
        switch layoutStyle {
        case .horizontal:
            return CGFloat(count) * 48 + 6
        case .vertical:
            return CGFloat(count) * 30
        }
    }

    // ABSOLUTELY FIXED LAYOUT - these positions NEVER change
    // Horizontal layout: icons with text beside them
    private let horizontalPositions: [(iconX: CGFloat, textX: CGFloat)] = [
        (iconX: 2, textX: 18),     // CPU position
        (iconX: 50, textX: 66),    // Memory position  
        (iconX: 98, textX: 114),   // Disk position
        (iconX: 146, textX: 162)   // Temperature position
    ]
    
    // Vertical layout: labels above percentages, very compact horizontal spacing
    private let verticalPositions: [(labelX: CGFloat, valueX: CGFloat)] = [
        (labelX: 2, valueX: 2),     // CPU position
        (labelX: 32, valueX: 32),   // Memory position  
        (labelX: 62, valueX: 62),   // Disk position
        (labelX: 92, valueX: 92)    // Temperature position
    ]
    
    private let iconSize: CGFloat = 14
    private let fontSize: CGFloat = 12
    private let labelFontSize: CGFloat = 9
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAppearanceObserver()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearanceObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAppearanceObserver() {
        // Listen for system appearance changes
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    @objc private func appearanceDidChange() {
        // Clear icon cache to force regeneration with new appearance
        iconCache.removeAll()
        needsDisplay = true
    }
    
    // Public method to clear icon cache when layout changes
    func clearIconCache() {
        iconCache.removeAll()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self, userInfo: nil))
    }

    override func mouseUp(with event: NSEvent) { clickHandler?(event) }
    override func rightMouseUp(with event: NSEvent) { clickHandler?(event) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Clear background
        NSColor.clear.setFill()
        bounds.fill()
        
        switch layoutStyle {
        case .horizontal:
            drawHorizontalLayout()
        case .vertical:
            drawVerticalLayout()
        }
    }
    
    private func drawHorizontalLayout() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let centerY = bounds.midY

        for (index, metric) in metrics.enumerated() {
            guard index < horizontalPositions.count else { break }
            
            let pos = horizontalPositions[index]
            
            // Draw icon at FIXED position with proper template rendering
            let icon = iconFor(kind: metric.kind)
            let iconRect = CGRect(x: pos.iconX, y: centerY - iconSize/2, width: iconSize, height: iconSize)
            
            // Proper template image rendering with tint color
            if icon.isTemplate {
                // Save the graphics state
                NSGraphicsContext.current?.saveGraphicsState()
                
                // For template images, we need to use compositeSourceOver with the label color
                NSColor.labelColor.setFill()
                
                // Fill the icon rect with the tint color
                iconRect.fill()
                
                // Then composite the icon as a mask using destinationIn
                icon.draw(in: iconRect, from: .zero, operation: .destinationIn, fraction: 1.0)
                
                // Restore the graphics state
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                // For non-template images, draw normally
                icon.draw(in: iconRect)
            }
            
            // Draw text at FIXED position
            let text = metric.formattedValue(horizontal: true)
            
            let textRect = CGRect(x: pos.textX, y: centerY - fontSize/2 - 1, width: 50, height: fontSize + 2)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
    
    private func drawVerticalLayout() {
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.labelColor]
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.labelColor]
        
        // Add bottom padding by shifting content up from center
        let bottomPadding: CGFloat = 3
        let centerY = bounds.midY + bottomPadding
        
        for (index, metric) in metrics.enumerated() {
            guard index < verticalPositions.count else { break }
            
            let pos = verticalPositions[index]
            
            // Draw label above value - with bottom padding
            let labelText = labelFor(kind: metric.kind)
            let labelRect = CGRect(x: pos.labelX, y: centerY - 2, width: 28, height: labelFontSize + 2)
            (labelText as NSString).draw(in: labelRect, withAttributes: labelAttrs)
            
            // Draw value below label - with bottom padding
            let valueText = metric.formattedValue(horizontal: false)
            
            let valueRect = CGRect(x: pos.valueX, y: centerY - fontSize - 4, width: 28, height: fontSize + 2)
            (valueText as NSString).draw(in: valueRect, withAttributes: valueAttrs)
        }
    }
    
    private func labelFor(kind: Metric.Kind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .mem: return "MEM"
        case .disk: return "SSD"
        case .temp: return "TMP"
        }
    }

    private func iconFor(kind: Metric.Kind) -> NSImage {
        if let cached = iconCache[kind] { return cached }
        let name: String
        switch kind {
        case .cpu: name = "cpu"
        case .mem:
            if #available(macOS 11.0, *), NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil) != nil { 
                name = "sdcard" 
            } else { 
                name = "memorychip" 
            }
        case .disk: name = "internaldrive"
        case .temp: name = "thermometer.medium"
        }
        
        let img: NSImage
        if #available(macOS 11.0, *), let systemImage = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            // Create SF Symbol with explicit configuration for menu bar
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configuredImage = systemImage.withSymbolConfiguration(config) ?? systemImage
            
            img = configuredImage.copy() as! NSImage
            img.isTemplate = true
            
            NSLog("MacStats: Created SF Symbol: \(name), isTemplate: \(img.isTemplate)")
        } else {
            // Fallback: create a simple template image
            img = NSImage(size: NSSize(width: 16, height: 16))
            img.lockFocus()
            NSColor.labelColor.setFill()
            let rect = NSRect(x: 2, y: 2, width: 12, height: 12)
            rect.fill()
            img.unlockFocus()
            img.isTemplate = true
            
            NSLog("MacStats: Created fallback image for: \(name), isTemplate: \(img.isTemplate)")
        }
        
        iconCache[kind] = img
        return img
    }
}