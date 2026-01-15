import AppKit

final class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    /// Copies an NSImage to the system clipboard
    /// - Parameter image: The image to copy
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func copy(image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general

        // Clear existing clipboard contents
        pasteboard.clearContents()

        // Get image representations
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            print("ClipboardManager: Failed to get TIFF representation")
            return false
        }

        // Create PNG data for better compatibility
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("ClipboardManager: Failed to create PNG data")
            return false
        }

        // Write multiple formats for maximum compatibility
        let success = pasteboard.writeObjects([image])

        // Also write raw PNG data
        if success {
            pasteboard.setData(pngData, forType: .png)
        }

        print("ClipboardManager: Image copied to clipboard - \(success)")
        return success
    }

    /// Alternative method using direct data writing
    @discardableResult
    func copyImageData(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }

        // Declare types we'll provide
        pasteboard.declareTypes([.tiff, .png], owner: nil)

        // Write both formats
        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.setData(pngData, forType: .png)

        return true
    }
}
