import AppKit
import ScreenCaptureKit
import CoreMedia

@MainActor
final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    private let permissionManager = PermissionManager.shared
    private let clipboardManager = ClipboardManager.shared

    /// In-flight `SCShareableContent` fetch started when the region overlay opens.
    private var pendingContent: Task<SCShareableContent, Error>?

    private init() {}

    // MARK: - Shareable Content

    /// Starts fetching shareable content ahead of an imminent capture.
    ///
    /// `SCShareableContent.excludingDesktopWindows` costs ~40ms, which otherwise lands entirely
    /// after mouse-up. Kicking it off when the selection overlay appears overlaps that cost with
    /// the user's drag, so the capture feels immediate. The result is consumed exactly once, and
    /// is fetched at overlay-open time so the display list cannot go stale in between.
    func prewarmShareableContent() {
        pendingContent?.cancel()
        pendingContent = Task {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let pending = pendingContent {
            pendingContent = nil
            if let content = try? await pending.value {
                return content
            }
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - Public Capture Methods

    /// Captures the full screen (display under mouse cursor) and copies to clipboard
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

    // MARK: - Display Helpers

    /// Returns the mouse location in CG coordinate space (top-left origin)
    private var mouseLocationCG: CGPoint {
        NSScreen.convertToCGGlobal(NSEvent.mouseLocation)
    }

    /// Finds the SCDisplay containing the given point in CG coordinates
    private func displayContaining(cgPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        displays.first { $0.frame.contains(cgPoint) }
    }

    // MARK: - ScreenCaptureKit Implementation

    private func captureFullScreenModern() async throws -> NSImage {
        // Capture mouse position before any async work to avoid race conditions
        let mouseCG = mouseLocationCG

        let content = try await shareableContent()

        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplaysFound
        }

        // Find the display under the mouse cursor
        let display = displayContaining(cgPoint: mouseCG, in: content.displays)
            ?? content.displays[0]

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // contentRect is in points; pointPixelScale converts it to the native pixel buffer size.
        // Both come from the filter itself, so no guessing about Retina vs. 1x monitors.
        config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        config.showsCursor = false

        return try await captureWithFilter(filter, configuration: config)
    }

    private func captureRegionModern(_ rect: CGRect) async throws -> NSImage {
        let content = try await shareableContent()

        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplaysFound
        }

        // Find the display containing the center of the selected region
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let display = displayContaining(cgPoint: center, in: content.displays)
            ?? content.displays[0]

        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Convert the global CG rect to display-local points, clamped to the display.
        // Cross-monitor selections are intentionally clipped, not stitched.
        let localRect = CGRect(
            x: rect.origin.x - display.frame.origin.x,
            y: rect.origin.y - display.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        let clampedRect = localRect.intersection(CGRect(origin: .zero, size: filter.contentRect.size))

        guard !clampedRect.isEmpty else {
            throw CaptureError.invalidRegion
        }

        // Capture the whole display at native resolution, then crop.
        //
        // Deliberately NOT using SCStreamConfiguration.sourceRect: ScreenCaptureKit fits the
        // source into the destination buffer using its own aspect-preserving, non-upscaling
        // policy and leaves the remainder transparent. That is what produced images of the
        // right size whose content sat in one corner surrounded by blank space. A crop in
        // pixel space is exact by construction and has no such policy to fight.
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        config.showsCursor = false

        let fullImage = try await captureCGImage(filter, configuration: config)

        // Derive pixels-per-point from the image that actually came back rather than trusting
        // a precomputed scale, so the crop stays correct even if SCK hands back another size.
        let scaleX = CGFloat(fullImage.width) / filter.contentRect.width
        let scaleY = CGFloat(fullImage.height) / filter.contentRect.height

        let cropRect = CGRect(
            x: clampedRect.minX * scaleX,
            y: clampedRect.minY * scaleY,
            width: clampedRect.width * scaleX,
            height: clampedRect.height * scaleY
        ).integral.intersection(
            CGRect(x: 0, y: 0, width: CGFloat(fullImage.width), height: CGFloat(fullImage.height))
        )

        guard cropRect.width >= 1, cropRect.height >= 1,
              let cropped = fullImage.cropping(to: cropRect) else {
            throw CaptureError.invalidRegion
        }

        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func captureWithFilter(_ filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> NSImage {
        // Use SCScreenshotManager for single frame capture (macOS 14+)
        if #available(macOS 14.0, *) {
            let cgImage = try await captureCGImage(filter, configuration: configuration)
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

    @available(macOS 14.0, *)
    private func captureCGImage(_ filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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
