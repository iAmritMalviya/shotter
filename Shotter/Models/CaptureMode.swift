import Foundation
import CoreGraphics

enum CaptureMode: Equatable {
    case fullScreen
    case region(CGRect)
    case window(CGWindowID)

    var displayName: String {
        switch self {
        case .fullScreen:
            return "Capture Full Screen"
        case .region:
            return "Capture Region"
        case .window:
            return "Capture Window"
        }
    }

    var shortcutHint: String {
        switch self {
        case .fullScreen:
            return "⌘⇧3"
        case .region:
            return "⌘⇧4"
        case .window:
            return "⌘⇧5"
        }
    }
}
