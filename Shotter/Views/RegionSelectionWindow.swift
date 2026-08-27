import AppKit

/// Full-screen overlay used to drag out a capture region.
///
/// This is an `NSPanel` with `.nonactivatingPanel`, not a plain `NSWindow`, so it can take
/// keyboard focus *without* activating Shotter. Activating an LSUIElement app to show the
/// overlay causes a visible app-switch (and sometimes a Space-switch) transition before the
/// crosshair appears, which is exactly the lag the system screenshot UI does not have.
final class RegionSelectionWindow: NSPanel {
    private var selectionView: RegionSelectionView!
    private var completionHandler: ((CGRect?) -> Void)?
    private var keyMonitor: Any?
    private var isSessionActive = false

    /// macOS's own screenshot-selection cursor — the dotted reticle Cmd+Shift+4 uses — loaded
    /// from the HIServices cursor resources so the overlay matches the system screenshot UI
    /// instead of the thinner, plainer `NSCursor.crosshair`.
    ///
    /// The path is stable but undocumented, so this falls back to `.crosshair` if the resource
    /// ever moves. Reading a system asset at a fixed path is already how the capture sound is
    /// sourced (see `MenuBarController.setupCaptureSound`).
    fileprivate static let captureCursor: NSCursor = {
        let directory = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks"
            + "/HIServices.framework/Versions/A/Resources/cursors/screenshotselection"

        guard let image = NSImage(contentsOfFile: "\(directory)/cursor.pdf"), image.isValid else {
            return .crosshair
        }

        // hotx/hoty are in the cursor's own flipped (top-left origin) space, which is the same
        // space NSCursor expects for its hot spot.
        let info = NSDictionary(contentsOfFile: "\(directory)/info.plist")
        let hotSpot = NSPoint(
            x: (info?["hotx"] as? NSNumber)?.doubleValue ?? image.size.width / 2,
            y: (info?["hoty"] as? NSNumber)?.doubleValue ?? image.size.height / 2
        )
        return NSCursor(image: image, hotSpot: hotSpot)
    }()

    /// The rect spanning every attached screen, in AppKit global coordinates.
    private static var unionFrame: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    init() {
        let screenFrame = Self.unionFrame

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure window for selection overlay
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hidesOnDeactivate = false      // NSPanel defaults to true; would yank the overlay away
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Set up selection view
        selectionView = RegionSelectionView(frame: CGRect(origin: .zero, size: screenFrame.size))
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.completeSelection(rect: rect)
        }
        selectionView.onSelectionCancelled = { [weak self] in
            self?.cancelSelection()
        }
        self.contentView = selectionView
    }

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        // The global hotkey keeps firing while the overlay is already up. Ignore re-entry:
        // starting a second session would stack another cursor push and another event monitor
        // against a single pop and a single removal, leaving the capture cursor stuck
        // system-wide once the selection finishes.
        guard !isSessionActive else { return }
        isSessionActive = true

        self.completionHandler = completion

        // The overlay is reused across captures, so re-fit it to the current screen
        // arrangement and clear any leftover selection before showing it again.
        let screenFrame = Self.unionFrame
        setFrame(screenFrame, display: false)
        selectionView.frame = CGRect(origin: .zero, size: screenFrame.size)
        selectionView.reset()

        // Add local monitor for Escape key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.cancelSelection()
                return nil
            }
            return event
        }

        // Show window and capture mouse. Deliberately no NSApp.activate() — a nonactivating
        // panel receives keyboard input without making Shotter the active app.
        self.makeKeyAndOrderFront(nil)
        self.makeFirstResponder(selectionView)
        Self.captureCursor.push()
    }

    override var canBecomeKey: Bool { true }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func finish(with rect: CGRect?) {
        guard isSessionActive, let handler = completionHandler else { return }
        isSessionActive = false
        completionHandler = nil          // guard against the view reporting twice
        removeKeyMonitor()
        NSCursor.pop()
        self.orderOut(nil)
        handler(rect)
    }

    private func cancelSelection() {
        finish(with: nil)
    }

    private func completeSelection(rect: CGRect) {
        finish(with: rect)
    }
}

// MARK: - Selection View

final class RegionSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentRect: CGRect?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    // The overlay panel is deliberately non-activating, so Shotter never becomes the active
    // app. NSCursor.push() alone does not survive that — the active app's cursor wins — which
    // is why the crosshair kept showing instead of the screenshot reticle. An .activeAlways
    // tracking area still delivers mouse events to an inactive app, so the cursor is re-applied
    // on entry and on every move. (cursorUpdate: is not delivered for .activeAlways areas, so
    // mouseEntered/mouseMoved are what actually carry this.)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func applyCaptureCursor() {
        RegionSelectionWindow.captureCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) { applyCaptureCursor() }
    override func mouseEntered(with event: NSEvent) { applyCaptureCursor() }
    override func mouseMoved(with event: NSEvent) { applyCaptureCursor() }

    func reset() {
        startPoint = nil
        currentRect = nil
        isDragging = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onSelectionCancelled?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current

        // .copy rather than the default .sourceOver: only the dirty region is repainted while
        // dragging, and blending 30% black over an area that already has 30% black would
        // darken it a little more on every mouse-moved event.
        context?.compositingOperation = .copy
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        context?.compositingOperation = .sourceOver

        // Draw selection rectangle
        if let rect = currentRect {
            // Clear the selection area
            context?.compositingOperation = .clear
            rect.fill()
            context?.compositingOperation = .sourceOver

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

    /// Repaints only the area the selection actually touched.
    ///
    /// The previous code set `needsDisplay = true` on every mouse-moved event, forcing a repaint
    /// of the entire multi-screen overlay (here 4000x1440 points) for each drag sample, which is
    /// what made dragging feel heavy. The inset covers the dashed border and the dimensions
    /// label, both of which draw outside the selection rect.
    private func invalidate(_ first: CGRect?, _ second: CGRect?) {
        var dirty = CGRect.null
        if let first { dirty = dirty.union(first) }
        if let second { dirty = dirty.union(second) }

        guard !dirty.isNull else {
            needsDisplay = true
            return
        }
        setNeedsDisplay(dirty.insetBy(dx: -140, dy: -60))
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
        let previous = currentRect
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
        currentRect = nil
        invalidate(previous, nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = startPoint else { return }

        let current = convert(event.locationInWindow, from: nil)

        // Calculate rectangle from start to current
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        let previous = currentRect
        currentRect = CGRect(x: minX, y: minY, width: width, height: height)
        invalidate(previous, currentRect)
        applyCaptureCursor()
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
        guard let window = self.window else { return rect }

        // Convert corners from view coords → window coords → AppKit screen coords
        let bottomLeft = window.convertPoint(toScreen: convert(CGPoint(x: rect.minX, y: rect.minY), to: nil))
        let topRight = window.convertPoint(toScreen: convert(CGPoint(x: rect.maxX, y: rect.maxY), to: nil))

        let screenRect = CGRect(
            x: bottomLeft.x,
            y: bottomLeft.y,
            width: topRight.x - bottomLeft.x,
            height: topRight.y - bottomLeft.y
        )

        // Flip Y: AppKit (bottom-left origin) → CG (top-left origin), anchored on the primary
        // display. This used to index NSScreen.screens[0], which is not guaranteed to be the
        // primary and traps on an empty array.
        return NSScreen.convertToCGGlobal(screenRect)
    }
}
