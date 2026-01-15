import Foundation

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplaysFound
    case captureFailed
    case invalidRegion
    case windowNotFound
    case cancelled
    case screenAsleep
    case screenLocked

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required"
        case .noDisplaysFound:
            return "No displays found to capture"
        case .captureFailed:
            return "Failed to capture screen"
        case .invalidRegion:
            return "Invalid selection region"
        case .windowNotFound:
            return "Selected window not found"
        case .cancelled:
            return "Capture cancelled"
        case .screenAsleep:
            return "Screen is asleep"
        case .screenLocked:
            return "Screen is locked"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Open System Settings → Privacy & Security → Screen Recording and enable Shotter"
        default:
            return nil
        }
    }
}
