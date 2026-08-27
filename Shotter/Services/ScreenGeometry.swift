import AppKit

// AppKit and CoreGraphics disagree about global screen coordinates: AppKit puts the origin at
// the bottom-left of the primary display with Y increasing upward, CoreGraphics puts it at the
// top-left with Y increasing downward. ScreenCaptureKit speaks CoreGraphics, the selection
// overlay and NSEvent speak AppKit, so everything crossing that boundary flips here.

extension NSScreen {
    /// The primary display — the screen AppKit anchors its global coordinate space on
    /// (origin `(0, 0)`, the one carrying the menu bar).
    ///
    /// `NSScreen.screens[0]` is *usually* this screen, but macOS does not guarantee the ordering
    /// and indexing it traps on an empty array. `NSScreen.main` is the screen holding the key
    /// window, which is a different thing and is frequently not the primary.
    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    /// Converts a rect from AppKit global coordinates to CoreGraphics global coordinates.
    static func convertToCGGlobal(_ rect: CGRect) -> CGRect {
        guard let primaryHeight = primary?.frame.height else { return rect }
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts a point from AppKit global coordinates to CoreGraphics global coordinates.
    static func convertToCGGlobal(_ point: CGPoint) -> CGPoint {
        guard let primaryHeight = primary?.frame.height else { return point }
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
