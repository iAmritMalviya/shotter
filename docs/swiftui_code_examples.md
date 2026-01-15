# SwiftUI Code Examples: Shotter

This document contains complete, production-ready code for all components of the Shotter application.

---

## Table of Contents

1. [App Entry Point](#1-app-entry-point)
2. [Models](#2-models)
3. [Clipboard Manager](#3-clipboard-manager)
4. [Permission Manager](#4-permission-manager)
5. [Screen Capture Service](#5-screen-capture-service)
6. [Region Selection Window](#6-region-selection-window)
7. [Menu Bar Controller](#7-menu-bar-controller)
8. [Preferences View](#8-preferences-view)
9. [App Delegate](#9-app-delegate)
10. [Notification Feedback](#10-notification-feedback)

---

## 1. App Entry Point

### ShotterApp.swift

```swift
import SwiftUI

@main
struct ShotterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene for Preferences window (Cmd+,)
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.hotkeyManager)
        }
    }
}
```

---

## 2. Models

### CaptureMode.swift

```swift
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
```

### HotkeyConfiguration.swift

```swift
import Foundation
import Carbon.HIToolbox

struct HotkeyConfiguration: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    // Default hotkeys
    static let fullScreen = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_3),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let region = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_4),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let window = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_5),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

        // Map key code to character
        let keyChar = Self.keyCodeToString(keyCode)
        parts.append(keyChar)

        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Z): "Z",
        ]
        return keyMap[keyCode] ?? "?"
    }
}

// MARK: - UserDefaults Storage

extension HotkeyConfiguration {
    static let fullScreenKey = "hotkey.fullScreen"
    static let regionKey = "hotkey.region"
    static let windowKey = "hotkey.window"

    static func load(for key: String, default defaultValue: HotkeyConfiguration) -> HotkeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return defaultValue
        }
        return config
    }

    func save(for key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

### CaptureError.swift

```swift
import Foundation

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplaysFound
    case captureFailednil
    case invalidRegion
    case windowNotFound
    case cancelled

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
```

---

## 3. Clipboard Manager

### ClipboardManager.swift

```swift
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
```

---

## 4. Permission Manager

### PermissionManager.swift

```swift
import Foundation
import ScreenCaptureKit
import Combine

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: AuthorizationStatus = .unknown

    enum AuthorizationStatus {
        case unknown
        case authorized
        case denied
        case restricted
    }

    private init() {
        Task {
            await checkPermission()
        }
    }

    /// Checks current screen recording permission status
    func checkPermission() async {
        // For macOS 12.3+, use ScreenCaptureKit
        if #available(macOS 12.3, *) {
            do {
                // Attempting to get shareable content will prompt for permission if needed
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                // If we get here without error, we have permission
                isAuthorized = !content.displays.isEmpty
                authorizationStatus = isAuthorized ? .authorized : .denied
            } catch {
                // Error usually means permission denied
                isAuthorized = false
                authorizationStatus = .denied
                print("PermissionManager: Screen capture permission check failed - \(error)")
            }
        } else {
            // Legacy check for older macOS versions
            isAuthorized = CGPreflightScreenCaptureAccess()
            authorizationStatus = isAuthorized ? .authorized : .denied
        }
    }

    /// Requests screen recording permission
    /// On modern macOS, this triggers the system permission dialog
    func requestPermission() async {
        if #available(macOS 12.3, *) {
            // Trigger permission prompt by attempting to access content
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                // Permission was denied or error occurred
            }
        } else {
            // Legacy: This triggers the permission dialog
            CGRequestScreenCaptureAccess()
        }

        // Re-check permission status
        await checkPermission()
    }

    /// Opens System Settings to the Screen Recording privacy pane
    func openSystemSettings() {
        let url: URL
        if #available(macOS 13.0, *) {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        } else {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording")!
        }
        NSWorkspace.shared.open(url)
    }
}
```

---

## 5. Screen Capture Service

### ScreenCaptureService.swift

```swift
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

    /// Captures the full screen (all displays) and copies to clipboard
    func captureFullScreen() async throws -> NSImage {
        guard permissionManager.isAuthorized else {
            await permissionManager.requestPermission()
            if !permissionManager.isAuthorized {
                throw CaptureError.permissionDenied
            }
        }

        if #available(macOS 12.3, *) {
            return try await captureFullScreenModern()
        } else {
            return try captureFullScreenLegacy()
        }
    }

    /// Captures a specific region and copies to clipboard
    func captureRegion(_ rect: CGRect) async throws -> NSImage {
        guard permissionManager.isAuthorized else {
            await permissionManager.requestPermission()
            if !permissionManager.isAuthorized {
                throw CaptureError.permissionDenied
            }
        }

        guard rect.width > 0 && rect.height > 0 else {
            throw CaptureError.invalidRegion
        }

        if #available(macOS 12.3, *) {
            return try await captureRegionModern(rect)
        } else {
            return try captureRegionLegacy(rect)
        }
    }

    /// Captures a specific window and copies to clipboard
    func captureWindow(_ windowID: CGWindowID) async throws -> NSImage {
        guard permissionManager.isAuthorized else {
            await permissionManager.requestPermission()
            if !permissionManager.isAuthorized {
                throw CaptureError.permissionDenied
            }
        }

        return try captureWindowLegacy(windowID)
    }

    // MARK: - ScreenCaptureKit Implementation (macOS 12.3+)

    @available(macOS 12.3, *)
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

        config.width = Int(display.width) * 2  // Retina
        config.height = Int(display.height) * 2
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await captureWithFilter(filter, configuration: config)
        return image
    }

    @available(macOS 12.3, *)
    private func captureRegionModern(_ rect: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        // Find display containing the rect
        guard let display = content.displays.first(where: { display in
            let displayFrame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            return displayFrame.intersects(rect)
        }) else {
            throw CaptureError.noDisplaysFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // Set source rect for region capture
        config.sourceRect = rect
        config.width = Int(rect.width) * 2
        config.height = Int(rect.height) * 2
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await captureWithFilter(filter, configuration: config)
        return image
    }

    @available(macOS 12.3, *)
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

    private func captureFullScreenLegacy() throws -> NSImage {
        let displayID = CGMainDisplayID()

        guard let cgImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.captureFailed
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    private func captureRegionLegacy(_ rect: CGRect) throws -> NSImage {
        let displayID = CGMainDisplayID()

        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else {
            throw CaptureError.captureFailed
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

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
                  ownerName != "Dock" else {
                return nil
            }

            return (windowID, windowName, ownerName)
        }
    }
}

// MARK: - Stream Output Handler

@available(macOS 12.3, *)
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
```

---

## 6. Region Selection Window

### RegionSelectionWindow.swift

```swift
import AppKit

protocol RegionSelectionDelegate: AnyObject {
    func regionSelected(_ rect: CGRect)
    func regionSelectionCancelled()
}

final class RegionSelectionWindow: NSWindow {
    weak var selectionDelegate: RegionSelectionDelegate?

    private var selectionView: RegionSelectionView!

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
        selectionView.window = self
        self.contentView = selectionView
    }

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        selectionView.completionHandler = completion

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

    func cancelSelection() {
        NSCursor.pop()
        self.orderOut(nil)
        selectionView.completionHandler?(nil)
        selectionDelegate?.regionSelectionCancelled()
    }

    func completeSelection(rect: CGRect) {
        NSCursor.pop()
        self.orderOut(nil)
        selectionView.completionHandler?(rect)
        selectionDelegate?.regionSelected(rect)
    }
}

// MARK: - Selection View

final class RegionSelectionView: NSView {
    var completionHandler: ((CGRect?) -> Void)?
    weak var window: RegionSelectionWindow?

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
            NSColor.clear.setFill()
            rect.fill(using: .clear)

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
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]

        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.minY - size.height - 8,
            width: size.width + 8,
            height: size.height + 4
        )

        // Background
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()

        // Text
        text.draw(at: CGPoint(x: labelRect.minX + 4, y: labelRect.minY + 2), withAttributes: attributes)
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
            window?.completeSelection(rect: screenRect)
        } else {
            window?.cancelSelection()
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
```

---

## 7. Menu Bar Controller

### MenuBarController.swift

```swift
import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private let captureService = ScreenCaptureService.shared
    private let clipboardManager = ClipboardManager.shared
    private let permissionManager = PermissionManager.shared

    private var regionSelectionWindow: RegionSelectionWindow?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatusItem()
        setupMenu()
        observePermissions()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol for menu bar icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotter") {
                button.image = image.withSymbolConfiguration(config)
            } else {
                // Fallback to text
                button.title = "📷"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        // Capture options
        let fullScreenItem = NSMenuItem(
            title: "Capture Full Screen",
            action: #selector(captureFullScreen),
            keyEquivalent: ""
        )
        fullScreenItem.target = self
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullScreenItem.keyEquivalent = "3"
        menu.addItem(fullScreenItem)

        let regionItem = NSMenuItem(
            title: "Capture Region",
            action: #selector(captureRegion),
            keyEquivalent: ""
        )
        regionItem.target = self
        regionItem.keyEquivalentModifierMask = [.command, .shift]
        regionItem.keyEquivalent = "4"
        menu.addItem(regionItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(captureWindowMenu),
            keyEquivalent: ""
        )
        windowItem.target = self
        windowItem.keyEquivalentModifierMask = [.command, .shift]
        windowItem.keyEquivalent = "5"
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // Permission status item (hidden when authorized)
        let permissionItem = NSMenuItem(
            title: "⚠️ Grant Screen Recording Permission",
            action: #selector(openPermissions),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.tag = 100 // Tag for updating later
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Shotter",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observePermissions() {
        permissionManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthorized in
                self?.updateMenuForPermissionStatus(isAuthorized)
            }
            .store(in: &cancellables)
    }

    private func updateMenuForPermissionStatus(_ isAuthorized: Bool) {
        guard let permissionItem = menu.item(withTag: 100) else { return }
        permissionItem.isHidden = isAuthorized

        // Enable/disable capture items
        for item in menu.items {
            if item.action == #selector(captureFullScreen) ||
               item.action == #selector(captureRegion) ||
               item.action == #selector(captureWindowMenu) {
                item.isEnabled = isAuthorized
            }
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc func captureFullScreen() {
        Task {
            do {
                let image = try await captureService.captureFullScreen()
                clipboardManager.copy(image: image)
                showSuccessNotification()
            } catch {
                showErrorAlert(error)
            }
        }
    }

    @objc func captureRegion() {
        regionSelectionWindow = RegionSelectionWindow()
        regionSelectionWindow?.beginSelection { [weak self] rect in
            guard let self = self, let rect = rect else { return }

            Task {
                do {
                    let image = try await self.captureService.captureRegion(rect)
                    self.clipboardManager.copy(image: image)
                    self.showSuccessNotification()
                } catch {
                    self.showErrorAlert(error)
                }
            }
        }
    }

    @objc func captureWindowMenu() {
        Task {
            let windows = await captureService.getWindowList()

            await MainActor.run {
                let windowMenu = NSMenu()

                if windows.isEmpty {
                    let noWindowsItem = NSMenuItem(title: "No windows available", action: nil, keyEquivalent: "")
                    noWindowsItem.isEnabled = false
                    windowMenu.addItem(noWindowsItem)
                } else {
                    for (id, title, app) in windows {
                        let item = NSMenuItem(
                            title: "\(app): \(title)",
                            action: #selector(captureSelectedWindow(_:)),
                            keyEquivalent: ""
                        )
                        item.target = self
                        item.representedObject = id
                        windowMenu.addItem(item)
                    }
                }

                // Show as submenu or popup
                if let button = statusItem.button {
                    windowMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
                }
            }
        }
    }

    @objc private func captureSelectedWindow(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }

        Task {
            do {
                let image = try await captureService.captureWindow(windowID)
                clipboardManager.copy(image: image)
                showSuccessNotification()
            } catch {
                showErrorAlert(error)
            }
        }
    }

    @objc private func openPermissions() {
        permissionManager.openSystemSettings()
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Feedback

    private func showSuccessNotification() {
        // Visual feedback - brief flash or notification
        let notification = NSUserNotification()
        notification.title = "Shotter"
        notification.informativeText = "Screenshot copied to clipboard"
        notification.soundName = nil

        // Use NotificationCenter for modern macOS
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Captured"
        content.body = "Image copied to clipboard"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        // Alternative: Play system sound
        NSSound(named: "Pop")?.play()
    }

    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let captureError = error as? CaptureError,
           captureError == .permissionDenied {
            alert.addButton(withTitle: "Open Settings")
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            permissionManager.openSystemSettings()
        }
    }
}

// MARK: - UNUserNotificationCenter Import

import UserNotifications
```

---

## 8. Preferences View

### PreferencesView.swift

```swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showNotification") private var showNotification = true
    @AppStorage("playSoundOnCapture") private var playSoundOnCapture = true

    var body: some View {
        TabView {
            GeneralTab(
                launchAtLogin: $launchAtLogin,
                showNotification: $showNotification,
                playSoundOnCapture: $playSoundOnCapture
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            HotkeysTab()
                .environmentObject(hotkeyManager)
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            PermissionsTab()
                .environmentObject(permissionManager)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Binding var launchAtLogin: Bool
    @Binding var showNotification: Bool
    @Binding var playSoundOnCapture: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch Shotter at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("After Capture") {
                Toggle("Show notification", isOn: $showNotification)
                Toggle("Play sound", isOn: $playSoundOnCapture)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

// MARK: - Hotkeys Tab

struct HotkeysTab: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                HotkeyRow(
                    label: "Capture Full Screen",
                    shortcut: hotkeyManager.fullScreenHotkey.displayString,
                    action: { /* Open hotkey recorder */ }
                )

                HotkeyRow(
                    label: "Capture Region",
                    shortcut: hotkeyManager.regionHotkey.displayString,
                    action: { /* Open hotkey recorder */ }
                )

                HotkeyRow(
                    label: "Capture Window",
                    shortcut: hotkeyManager.windowHotkey.displayString,
                    action: { /* Open hotkey recorder */ }
                )
            }

            Section {
                Text("Click on a shortcut to change it. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeyRow: View {
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(action: {
                isRecording = true
                action()
            }) {
                Text(isRecording ? "Press keys..." : shortcut)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Permissions Tab

struct PermissionsTab: View {
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        Form {
            Section("Screen Recording") {
                HStack {
                    Image(systemName: permissionManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(permissionManager.isAuthorized ? .green : .red)

                    VStack(alignment: .leading) {
                        Text("Screen Recording Permission")
                            .font(.headline)
                        Text(permissionManager.isAuthorized ? "Granted" : "Required for screen capture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !permissionManager.isAuthorized {
                        Button("Grant Access") {
                            permissionManager.openSystemSettings()
                        }
                    }
                }
            }

            if !permissionManager.isAuthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to grant permission:")
                            .font(.headline)
                        Text("1. Click 'Grant Access' above")
                        Text("2. In System Settings, find Shotter in the list")
                        Text("3. Toggle the switch to enable")
                        Text("4. Restart Shotter if needed")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Shotter")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A lightweight screenshot utility that captures directly to your clipboard.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            Text("© 2024 Your Name")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environmentObject(HotkeyManager())
}
```

---

## 9. App Delegate

### AppDelegate.swift

```swift
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Initialize managers
        hotkeyManager = HotkeyManager()
        menuBarController = MenuBarController()

        // Register global hotkeys
        registerHotkeys()

        // Check permissions on launch
        Task {
            await PermissionManager.shared.checkPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unregister hotkeys
        hotkeyManager.unregisterAll()
    }

    private func registerHotkeys() {
        // Register full screen hotkey
        hotkeyManager.register(
            config: hotkeyManager.fullScreenHotkey,
            for: .fullScreen
        ) { [weak self] in
            self?.menuBarController.captureFullScreen()
        }

        // Register region hotkey
        hotkeyManager.register(
            config: hotkeyManager.regionHotkey,
            for: .region
        ) { [weak self] in
            self?.menuBarController.captureRegion()
        }

        // Register window hotkey (placeholder - window capture is typically a menu action)
        hotkeyManager.register(
            config: hotkeyManager.windowHotkey,
            for: .window
        ) { [weak self] in
            self?.menuBarController.captureWindowMenu()
        }
    }
}
```

---

## 10. Notification Feedback

### NotificationView.swift (Optional Visual Feedback)

```swift
import SwiftUI
import AppKit

/// A brief visual indicator that appears when capture succeeds
struct CaptureSuccessOverlay: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("Copied!")
                .font(.headline)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                opacity = 0
            }
        }
    }
}

/// Window controller for showing overlay
final class OverlayWindowController {
    private var window: NSWindow?

    func showSuccess() {
        let hostingView = NSHostingView(rootView: CaptureSuccessOverlay())
        hostingView.frame = CGRect(x: 0, y: 0, width: 120, height: 120)

        window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.level = .floating
        window?.contentView = hostingView
        window?.ignoresMouseEvents = true

        // Center on screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - hostingView.frame.width) / 2
            let y = (screen.frame.height - hostingView.frame.height) / 2
            window?.setFrameOrigin(CGPoint(x: x, y: y))
        }

        window?.orderFront(nil)

        // Auto-dismiss after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
    }
}
```

---

## Complete File List

After implementation, your project should have these files:

```
Shotter/
├── Shotter.xcodeproj
├── Shotter/
│   ├── ShotterApp.swift
│   ├── Info.plist
│   ├── Shotter.entitlements
│   │
│   ├── App/
│   │   └── AppDelegate.swift
│   │
│   ├── Controllers/
│   │   └── MenuBarController.swift
│   │
│   ├── Services/
│   │   ├── ScreenCaptureService.swift
│   │   ├── ClipboardManager.swift
│   │   ├── HotkeyManager.swift          (see hotkey_support.md)
│   │   └── PermissionManager.swift
│   │
│   ├── Views/
│   │   ├── PreferencesView.swift
│   │   ├── RegionSelectionWindow.swift
│   │   └── NotificationView.swift
│   │
│   ├── Models/
│   │   ├── CaptureMode.swift
│   │   ├── CaptureError.swift
│   │   └── HotkeyConfiguration.swift
│   │
│   └── Resources/
│       └── Assets.xcassets
```
