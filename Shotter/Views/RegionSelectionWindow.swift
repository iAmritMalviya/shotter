import AppKit

/// macOS's own screenshot-selection cursor — the dotted reticle Cmd+Shift+4 uses — loaded from
/// the HIServices cursor resources so the overlay matches the system screenshot UI instead of
/// the thinner, plainer `NSCursor.crosshair`.
///
/// The path is stable but undocumented, so this falls back to `.crosshair` if the resource ever
/// moves. Reading a system asset at a fixed path is already how the capture sound is sourced
/// (see `MenuBarController.setupCaptureSound`).
private let captureCursor: NSCursor = {
    let directory = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks"
        + "/HIServices.framework/Versions/A/Resources/cursors/screenshotselection"

    guard let image = NSImage(contentsOfFile: "\(directory)/cursor.pdf"), image.isValid else {
        return .crosshair
    }

    // hotx/hoty are in the cursor's own flipped (top-left origin) space, which is the same
    // space NSCursor expects for its hot spot.
    let info = NSDictionary(contentsOfFile: "\(directory)/info.plist")
    return NSCursor(
        image: image,
        hotSpot: NSPoint(
            x: (info?["hotx"] as? NSNumber)?.doubleValue ?? image.size.width / 2,
            y: (info?["hoty"] as? NSNumber)?.doubleValue ?? image.size.height / 2
        )
    )
}()

/// Drives region selection across every attached display.
///
/// One panel is created **per screen** rather than a single panel spanning their union. With
/// "Displays have Separate Spaces" enabled — the macOS default — a window cannot span two
/// displays: the system confines it to one, so a union-sized overlay ended up covering only
/// part of the desktop, sized for the wrong display.
///
/// The panels are otherwise independent. AppKit keeps delivering a drag to the window where the
/// mouse went down even after the pointer leaves it, so the panel the drag started on tracks the
/// whole selection; the others just dim their screen. That matches how capture already behaves —
/// a selection is clipped to the display under its centre, never stitched across displays.
@MainActor
final class RegionSelectionWindow {
    private var panels: [RegionSelectionPanel] = []
    private var completionHandler: ((CGRect?) -> Void)?
    private var keyMonitor: Any?
    private var isSessionActive = false

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        // The global hotkey keeps firing while the overlay is already up. Tear any previous
        // session down rather than ignoring the press: stacking a second cursor push and event
        // monitor against a single pop and removal would leave the capture cursor stuck
        // system-wide, but ignoring re-entry would make the hotkey dead for good if a session
        // ever failed to finish.
        if isSessionActive {
            teardownSession()
            completionHandler = nil
        }
        isSessionActive = true
        completionHandler = completion

        rebuildPanelsIfScreensChanged()
        for panel in panels {
            panel.resetSelection()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        // Show every panel; make the one under the pointer key so it receives Escape.
        // Deliberately no NSApp.activate() — a nonactivating panel takes keyboard input
        // without making Shotter the active app, which avoids an app-switch transition.
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            panel.orderFrontRegardless()
        }
        let focused = panels.first { $0.frame.contains(mouse) } ?? panels.first
        focused?.makeKeyAndOrderFront(nil)
        focused?.focusSelectionView()

        captureCursor.push()
    }

    /// Rebuilds the per-screen panels when the display arrangement has changed.
    private func rebuildPanelsIfScreensChanged() {
        let screens = NSScreen.screens
        let unchanged = panels.count == screens.count
            && zip(panels, screens).allSatisfy { $0.frame == $1.frame }
        guard !unchanged else { return }

        for panel in panels {
            panel.orderOut(nil)
        }
        panels = screens.map { screen in
            RegionSelectionPanel(screen: screen) { [weak self] rect in
                self?.finish(with: rect)
            }
        }
    }

    /// Undoes what `beginSelection` set up, without notifying the caller.
    private func teardownSession() {
        guard isSessionActive else { return }
        isSessionActive = false

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        NSCursor.pop()
    }

    private func finish(with rect: CGRect?) {
        guard isSessionActive, let handler = completionHandler else { return }
        completionHandler = nil          // guard against a panel reporting twice
        teardownSession()
        for panel in panels {
            panel.orderOut(nil)
        }
        handler(rect)
    }
}

// MARK: - Per-screen Panel

/// A borderless overlay covering exactly one screen.
final class RegionSelectionPanel: NSPanel {
    private let selectionView: RegionSelectionView

    /// - Parameter onFinish: passed the selected rect in CG global coordinates, or nil on cancel.
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        selectionView = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hidesOnDeactivate = false      // NSPanel defaults to true; would yank the overlay away
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        selectionView.onSelectionComplete = { rect in onFinish(rect) }
        selectionView.onSelectionCancelled = { onFinish(nil) }
        self.contentView = selectionView
    }

    override var canBecomeKey: Bool { true }

    func resetSelection() {
        selectionView.reset()
    }

    func focusSelectionView() {
        makeFirstResponder(selectionView)
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

    func reset() {
        startPoint = nil
        currentRect = nil
        isDragging = false
        needsDisplay = true
    }

    // The overlay panels are deliberately non-activating, so Shotter never becomes the active
    // app. NSCursor.push() alone does not survive that — the active app's cursor wins — which is
    // why the crosshair kept showing instead of the screenshot reticle. An .activeAlways
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
        captureCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) { applyCaptureCursor() }
    override func mouseEntered(with event: NSEvent) { applyCaptureCursor() }
    override func mouseMoved(with event: NSEvent) { applyCaptureCursor() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onSelectionCancelled?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current

        // .copy rather than the default .sourceOver: only the dirty region is repainted while
        // dragging, and blending 30% black over an area that already has 30% black would darken
        // it a little more on every mouse-moved event.
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
    /// Setting `needsDisplay = true` on every mouse-moved event repaints the whole overlay for
    /// each drag sample, which is what made dragging feel heavy. The inset covers the dashed
    /// border and the dimensions label, both of which draw outside the selection rect.
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
            onSelectionComplete?(convertToScreenCoordinates(rect))
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
        // display. This must not index NSScreen.screens[0], which is not guaranteed to be the
        // primary and traps on an empty array.
        return NSScreen.convertToCGGlobal(screenRect)
    }
}
