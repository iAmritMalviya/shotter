import AppKit
import ScreenCaptureKit
import CoreMedia

@MainActor
final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    private let permissionManager = PermissionManager.shared
    private let clipboardManager = ClipboardManager.shared

    private init() {}

    // MARK: - Public Capture Methods

    /// Captures the full screen (primary display) and copies to clipboard
    func captureFullScreen() async throws -> NSImage {
        if !permissionManager.isAuthorized {
            await permissionManager.requestPermission()
            guard permissionManager.isAuthorized else {
                throw CaptureError.permissionDenied
            }
        }

        return try await captureFullScreenModern()
    }

    /// Captures a specific region and copies to clipboard
    func captureRegion(_ rect: CGRect) async throws -> NSImage {
        if !permissionManager.isAuthorized {
            await permissionManager.requestPermission()
            guard permissionManager.isAuthorized else {
                throw CaptureError.permissionDenied
            }
        }

        guard rect.width > 0 && rect.height > 0 else {
            throw CaptureError.invalidRegion
        }

        return try await captureRegionModern(rect)
    }

    /// Captures a specific window and copies to clipboard
    func captureWindow(_ windowID: CGWindowID) async throws -> NSImage {
        if !permissionManager.isAuthorized {
            await permissionManager.requestPermission()
            guard permissionManager.isAuthorized else {
                throw CaptureError.permissionDenied
            }
        }

        return try captureWindowLegacy(windowID)
    }

    // MARK: - ScreenCaptureKit Implementation

    private func captureFullScreenModern() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw CaptureError.noDisplaysFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        config.width = display.width * 2  // Retina
        config.height = display.height * 2
        config.showsCursor = false

        let image = try await captureWithFilter(filter, configuration: config)
        return image
    }

    private func captureRegionModern(_ rect: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        // Find display containing the rect
        guard let display = content.displays.first else {
            throw CaptureError.noDisplaysFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // Set source rect for region capture
        config.sourceRect = rect
        config.width = Int(rect.width) * 2
        config.height = Int(rect.height) * 2
        config.showsCursor = false

        let image = try await captureWithFilter(filter, configuration: config)
        return image
    }

    private func captureWithFilter(_ filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> NSImage {
        // Use SCScreenshotManager for single frame capture (macOS 14+)
        if #available(macOS 14.0, *) {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        // Fallback for macOS 12.3-13.x: Use stream-based capture
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                    let output = StreamOutput()

                    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
                    try await stream.startCapture()

                    // Wait for first frame
                    let image = try await output.waitForImage()

                    try await stream.stopCapture()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Legacy Implementation (CGWindowList)

    private func captureWindowLegacy(_ windowID: CGWindowID) throws -> NSImage {
        let imageRef = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )

        guard let cgImage = imageRef else {
            throw CaptureError.windowNotFound
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Window List

    /// Returns list of capturable windows
    func getWindowList() async -> [(id: CGWindowID, title: String, app: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info -> (CGWindowID, String, String)? in
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = info[kCGWindowOwnerName as String] as? String else {
                return nil
            }

            let windowName = info[kCGWindowName as String] as? String ?? "Untitled"

            // Filter out system windows
            guard ownerName != "Window Server",
                  ownerName != "Dock",
                  ownerName != "Shotter" else {
                return nil
            }

            return (windowID, windowName, ownerName)
        }
    }
}

// MARK: - Stream Output Handler

private class StreamOutput: NSObject, SCStreamOutput {
    private var capturedImage: NSImage?
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var hasReceivedFrame = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !hasReceivedFrame else { return }
        hasReceivedFrame = true

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            continuation?.resume(throwing: CaptureError.captureFailed)
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            continuation?.resume(throwing: CaptureError.captureFailed)
            return
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        continuation?.resume(returning: image)
    }

    func waitForImage() async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}
