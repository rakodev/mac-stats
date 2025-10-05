import Cocoa

// Fixed pixel layout - absolutely no dynamic calculations to prevent ANY movement
final class StatusItemView: NSView {
    struct Metric {
        enum Kind { case cpu, mem, disk }
        let kind: Kind
        let percentage: Double
    }

    var metrics: [Metric] = [] { didSet { needsDisplay = true } }
    var displayDetailed: Bool = false { didSet { needsDisplay = true } }
    var clickHandler: ((NSEvent) -> Void)?

    private var iconCache: [Metric.Kind: NSImage] = [:]

    // ABSOLUTELY FIXED LAYOUT - these positions NEVER change
    // Compact spacing while ensuring 100% never overlaps
    private let positions: [(iconX: CGFloat, textX: CGFloat)] = [
        (iconX: 2, textX: 18),     // CPU position
        (iconX: 50, textX: 66),    // Memory position  
        (iconX: 98, textX: 114)    // Disk position
    ]
    
    private let iconSize: CGFloat = 14
    private let fontSize: CGFloat = 12

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
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let centerY = bounds.midY

        for (index, metric) in metrics.enumerated() {
            guard index < positions.count else { break }
            
            let pos = positions[index]
            
            // Draw icon at FIXED position
            let icon = iconFor(kind: metric.kind)
            let iconRect = CGRect(x: pos.iconX, y: centerY - iconSize/2, width: iconSize, height: iconSize)
            icon.draw(in: iconRect)
            
            // Draw text at FIXED position - always format as consistent width
            let value = Int(round(max(0, min(100, metric.percentage))))
            let text = String(format: "%3d%%", value)
            
            let textRect = CGRect(x: pos.textX, y: centerY - fontSize/2 - 1, width: 50, height: fontSize + 2)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
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
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
        iconCache[kind] = img
        return img
    }
}