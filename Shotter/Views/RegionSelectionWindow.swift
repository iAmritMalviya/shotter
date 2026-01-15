import AppKit

final class RegionSelectionWindow: NSWindow {
    private var selectionView: RegionSelectionView!
    private var completionHandler: ((CGRect?) -> Void)?

    init() {
        // Get the frame covering all screens
        let screenFrame = NSScreen.screens.reduce(CGRect.zero) { result, screen in
            result.union(screen.frame)
        }

        super.init(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Configure window for selection overlay
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Set up selection view
        selectionView = RegionSelectionView(frame: screenFrame)
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.completeSelection(rect: rect)
        }
        selectionView.onSelectionCancelled = { [weak self] in
            self?.cancelSelection()
        }
        self.contentView = selectionView
    }

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        self.completionHandler = completion

        // Show window and capture mouse
        self.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()

        // Make app active to receive events
        NSApp.activate(ignoringOtherApps: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            cancelSelection()
        }
    }

    private func cancelSelection() {
        NSCursor.pop()
        self.orderOut(nil)
        completionHandler?(nil)
    }

    private func completeSelection(rect: CGRect) {
        NSCursor.pop()
        self.orderOut(nil)
        completionHandler?(rect)
    }
}

// MARK: - Selection View

final class RegionSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentRect: CGRect?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Draw selection rectangle
        if let rect = currentRect {
            // Clear the selection area
            NSGraphicsContext.current?.compositingOperation = .clear
            rect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            // Draw border
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.setLineDash([5, 5], count: 2, phase: 0)
            path.stroke()

            // Draw dimensions label
            drawDimensionsLabel(for: rect)
        }
    }

    private func drawDimensionsLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]

        let size = text.size(withAttributes: attributes)
        var labelPoint = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.minY - size.height - 8
        )

        // Keep label on screen
        if labelPoint.y < 0 {
            labelPoint.y = rect.maxY + 8
        }

        // Background for label
        let bgRect = CGRect(
            x: labelPoint.x - 4,
            y: labelPoint.y - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

        // Text
        text.draw(at: labelPoint, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = startPoint else { return }

        let current = convert(event.locationInWindow, from: nil)

        // Calculate rectangle from start to current
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        currentRect = CGRect(x: minX, y: minY, width: width, height: height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false

        if let rect = currentRect, rect.width > 10 && rect.height > 10 {
            // Convert to screen coordinates
            let screenRect = convertToScreenCoordinates(rect)
            onSelectionComplete?(screenRect)
        } else {
            onSelectionCancelled?()
        }
    }

    private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else { return rect }

        // Flip Y coordinate (AppKit uses bottom-left origin, CGImage uses top-left)
        let flippedY = screen.frame.height - rect.maxY

        return CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )
    }
}
