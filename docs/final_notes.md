# Final Notes: Shotter

This document covers edge cases, known limitations, improvement opportunities, and future upgrade paths for the Shotter application.

---

## Edge Cases and Handling

### 1. Multiple Displays

**Scenario**: User has multiple monitors connected.

**Behavior**:
- `captureFullScreen()` captures the primary display by default
- User might expect all displays captured

**Solution Options**:
```swift
// Option A: Capture primary display only (current implementation)
let display = content.displays.first

// Option B: Capture all displays as combined image
func captureAllDisplays() async throws -> NSImage {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

    var images: [(NSImage, CGRect)] = []

    for display in content.displays {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await captureWithFilter(filter, configuration: config)
        let frame = CGRect(x: CGFloat(display.frame.origin.x),
                          y: CGFloat(display.frame.origin.y),
                          width: CGFloat(display.width),
                          height: CGFloat(display.height))
        images.append((image, frame))
    }

    return combineImages(images)
}

// Option C: Let user choose which display
func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> NSImage
```

**Recommendation**: Add a menu submenu for display selection when multiple displays are detected.

### 2. HDR Content

**Scenario**: Screen contains HDR content (wide color gamut).

**Behavior**: Standard capture may clip colors or look washed out.

**Solution**:
```swift
let config = SCStreamConfiguration()
config.pixelFormat = kCVPixelFormatType_ARGB2101010LEPacked // 10-bit HDR
config.colorSpaceName = CGColorSpace.displayP3 as CFString
```

**Note**: Most paste destinations don't support HDR, so this may not be necessary.

### 3. Retina vs Non-Retina

**Scenario**: Capturing from Retina display produces 2x resolution images.

**Current Behavior**: Images are captured at native resolution (e.g., 5120x2880 for 27" iMac).

**Considerations**:
- Large file sizes when pasting
- Some apps may display at wrong scale

**Solution Options**:
```swift
// Option A: Always capture at screen scale (current)
config.width = Int(display.width) * scaleFactor

// Option B: Add preference for capture resolution
enum CaptureResolution {
    case native      // Full Retina resolution
    case standard    // 1x resolution (scaled down)
    case custom(Int) // Custom width, maintain aspect ratio
}
```

### 4. Fullscreen Applications

**Scenario**: User wants to capture a fullscreen app (video, game, presentation).

**Behavior**: Capture should work, but some apps use private APIs that block capture.

**Edge cases**:
- DRM content (Netflix, Disney+) - Intentionally blocked
- Metal/OpenGL games - May require specific handling
- Spaces/fullscreen apps - Must handle correct display

**Testing needed**:
```
[ ] Safari fullscreen video
[ ] QuickTime Player fullscreen
[ ] Keynote presentation mode
[ ] Games (Steam, App Store)
[ ] Terminal fullscreen
```

### 5. System UI Elements

**Scenario**: Menu bar, Dock, notification banners appear in captures.

**Behavior**: By default, all visible content is captured.

**Solution**:
```swift
// Exclude certain windows from capture
let excludedApps = ["Dock", "SystemUIServer", "NotificationCenter"]
let excludedWindows = content.windows.filter { window in
    excludedApps.contains(window.owningApplication?.applicationName ?? "")
}

let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
```

### 6. Fast User Switching

**Scenario**: Another user logs in while Shotter is running.

**Behavior**: Screen capture may fail or capture wrong session.

**Solution**:
```swift
// Monitor for session changes
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.sessionDidBecomeActiveNotification,
    object: nil,
    queue: .main
) { _ in
    // Re-check permissions, refresh display list
    Task {
        await PermissionManager.shared.checkPermission()
    }
}
```

### 7. Screen Sleep / Lock

**Scenario**: User triggers capture while screen is asleep or locked.

**Behavior**: Capture fails with black image.

**Solution**:
```swift
func captureWithScreenCheck() async throws -> NSImage {
    // Check if screen is asleep
    guard !CGDisplayIsAsleep(CGMainDisplayID()) else {
        throw CaptureError.screenAsleep
    }

    // Check if session is locked
    let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any]
    let isLocked = sessionDict?["CGSSessionScreenIsLocked"] as? Bool ?? false
    guard !isLocked else {
        throw CaptureError.screenLocked
    }

    return try await captureFullScreen()
}
```

### 8. Very Large Captures

**Scenario**: Capturing 6K display or multiple displays combined.

**Behavior**: May cause memory pressure or slow clipboard operations.

**Solution**:
```swift
// Add automatic downscaling for very large images
func copyToClipboard(_ image: NSImage, maxDimension: CGFloat = 4096) -> Bool {
    let size = image.size
    if size.width > maxDimension || size.height > maxDimension {
        let scale = maxDimension / max(size.width, size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        scaledImage.unlockFocus()
        return ClipboardManager.shared.copy(image: scaledImage)
    }
    return ClipboardManager.shared.copy(image: image)
}
```

---

## Known Limitations

### 1. Sandbox Incompatibility

Screen capture cannot work in a sandboxed app. This means:
- Cannot distribute on Mac App Store
- Must use Developer ID distribution
- Users see Gatekeeper warnings until notarized

### 2. No Audio Capture

Current implementation captures only visual content. Audio requires:
- Additional permissions (Microphone)
- Different capture APIs
- Output format considerations

### 3. Global Hotkey Conflicts

If system screenshots are enabled, conflicting shortcuts may behave unexpectedly:
- Both Shotter and system capture may trigger
- System capture may take precedence

### 4. Permission UX

macOS doesn't provide a callback when permission is granted in System Settings. We must poll or wait for user to manually restart/retry.

### 5. Carbon Deprecation

Global hotkeys rely on deprecated Carbon APIs. While still functional, Apple may remove them in future macOS versions.

---

## Improvement Opportunities

### Short-Term Improvements

#### 1. Capture History

```swift
// Store recent captures in memory for quick access
class CaptureHistory {
    static let shared = CaptureHistory()
    private var history: [(NSImage, Date)] = []
    private let maxItems = 10

    func add(_ image: NSImage) {
        history.insert((image, Date()), at: 0)
        if history.count > maxItems {
            history.removeLast()
        }
    }

    func getMostRecent() -> NSImage? {
        history.first?.0
    }
}
```

#### 2. Capture Sound Effect

```swift
// Play custom sound on capture
func playCaptureSound() {
    if let soundURL = Bundle.main.url(forResource: "capture", withExtension: "aiff") {
        let sound = NSSound(contentsOf: soundURL, byReference: true)
        sound?.play()
    } else {
        NSSound(named: "Pop")?.play()
    }
}
```

#### 3. Visual Flash Feedback

```swift
// Brief screen flash like system screenshot
func flashScreen() {
    for screen in NSScreen.screens {
        let flashWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        flashWindow.backgroundColor = .white
        flashWindow.alphaValue = 0
        flashWindow.level = .screenSaver
        flashWindow.ignoresMouseEvents = true
        flashWindow.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            flashWindow.animator().alphaValue = 0.3
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                flashWindow.animator().alphaValue = 0
            } completionHandler: {
                flashWindow.orderOut(nil)
            }
        }
    }
}
```

#### 4. Annotation Support

Basic annotation before copying:

```swift
struct AnnotationView: View {
    let image: NSImage
    @State private var annotations: [Annotation] = []

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            Canvas { context, size in
                for annotation in annotations {
                    annotation.draw(in: context)
                }
            }
        }
        .gesture(annotationGesture)
    }
}
```

### Medium-Term Improvements

#### 1. OCR Text Recognition

```swift
import Vision

func extractText(from image: NSImage) async throws -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CaptureError.captureFailed
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate

    let handler = VNImageRequestHandler(cgImage: cgImage)
    try handler.perform([request])

    let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    return text ?? ""
}

// Copy text instead of image
func captureAndExtractText() async throws {
    let image = try await captureFullScreen()
    let text = try await extractText(from: image)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
```

#### 2. Cloud Integration

```swift
// Quick upload to imgur/cloudinary/custom server
protocol ImageUploader {
    func upload(_ image: NSImage) async throws -> URL
}

class ImgurUploader: ImageUploader {
    func upload(_ image: NSImage) async throws -> URL {
        // Implementation
    }
}
```

#### 3. Window Picker UI

Instead of text menu, show visual window picker:

```swift
struct WindowPickerView: View {
    let windows: [(CGWindowID, String, NSImage?)]
    let onSelect: (CGWindowID) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))]) {
                ForEach(windows, id: \.0) { window in
                    WindowThumbnail(
                        title: window.1,
                        thumbnail: window.2,
                        onTap: { onSelect(window.0) }
                    )
                }
            }
        }
    }
}
```

### Long-Term Improvements

#### 1. Screen Recording Support

```swift
// Extend to video recording
class ScreenRecorder {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?

    func startRecording(to url: URL) async throws
    func stopRecording() async throws -> URL
}
```

#### 2. Plugin System

```swift
protocol ShotterPlugin {
    var name: String { get }
    func process(_ image: NSImage) async throws -> NSImage
    func afterCapture(_ image: NSImage) async
}

// Example plugins:
// - Auto-upload to cloud
// - Add watermark
// - Resize/compress
// - Share to specific app
```

#### 3. Keyboard Shortcuts Editor

Full-featured shortcut recorder supporting all key combinations:

```swift
struct AdvancedHotkeyRecorder: NSViewRepresentable {
    @Binding var shortcut: HotkeyConfiguration?

    func makeNSView(context: Context) -> NSView {
        // Custom NSView that captures all key events
    }
}
```

---

## Future macOS Compatibility

### API Deprecation Risks

| API | Status | Replacement | Timeline |
|-----|--------|-------------|----------|
| Carbon Events | Deprecated | None official | Unknown |
| CGWindowListCreateImage | Stable | ScreenCaptureKit | Already available |
| NSPasteboard | Stable | No changes expected | N/A |
| SCShareableContent | Current | N/A | N/A |

### Recommended Migration Path

1. **Now**: Use ScreenCaptureKit as primary, CGWindowList as fallback
2. **Future**: Monitor WWDC for new global hotkey APIs
3. **If Carbon removed**: Consider Accessibility-based event taps (requires additional permission)

### macOS Version Support Matrix

| macOS Version | ScreenCaptureKit | CGWindowList | Carbon Hotkeys |
|---------------|------------------|--------------|----------------|
| 12.3+ (Monterey) | Yes | Yes | Yes |
| 11.x (Big Sur) | No | Yes | Yes |
| 10.15 (Catalina) | No | Yes | Yes |
| Future (15+) | Yes | Likely | Unknown |

---

## Performance Considerations

### Memory Usage

```swift
// Profile memory during capture
func measureCapture() async {
    let before = mach_task_basic_info().resident_size

    let image = try? await captureFullScreen()

    let after = mach_task_basic_info().resident_size
    print("Capture used \((after - before) / 1024 / 1024) MB")
}
```

### Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Idle memory | < 30 MB | `footprint` command |
| Peak during capture | < 200 MB | Instruments |
| Capture latency | < 100 ms | Time from hotkey to clipboard |
| App launch time | < 500 ms | Cold start to menu bar visible |

### Optimization Techniques

```swift
// 1. Use autoreleasepool for large captures
func captureWithMemoryManagement() async throws -> NSImage {
    return try await autoreleasepool {
        try await captureFullScreen()
    }
}

// 2. Compress before clipboard for large images
func compressIfNeeded(_ image: NSImage) -> NSImage {
    let maxBytes = 10_000_000 // 10 MB
    // Implementation
}

// 3. Lazy thumbnail generation for window picker
func generateThumbnailAsync(_ windowID: CGWindowID) async -> NSImage? {
    // Generate on background thread
}
```

---

## Testing Strategy

### Unit Tests

```swift
import XCTest

class ClipboardManagerTests: XCTestCase {
    func testCopyImage() {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        let result = ClipboardManager.shared.copy(image: image)
        XCTAssertTrue(result)

        let pasteboard = NSPasteboard.general
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }
}

class HotkeyConfigurationTests: XCTestCase {
    func testDisplayString() {
        let config = HotkeyConfiguration.fullScreen
        XCTAssertEqual(config.displayString, "⌘⇧3")
    }

    func testPersistence() {
        let config = HotkeyConfiguration(keyCode: 0x14, modifiers: 0x100)
        config.save(for: "test.hotkey")

        let loaded = HotkeyConfiguration.load(for: "test.hotkey", default: .fullScreen)
        XCTAssertEqual(config, loaded)
    }
}
```

### UI Tests

```swift
import XCTest

class ShotterUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        app.launch()
    }

    func testMenuBarPresent() {
        let menuBarItem = app.statusItems["Shotter"]
        XCTAssertTrue(menuBarItem.exists)
    }

    func testPreferencesOpens() {
        // Click menu bar icon
        // Select Preferences
        // Verify window appears
    }
}
```

### Manual Test Checklist

```
## Capture Tests
[ ] Full screen capture - primary display
[ ] Full screen capture - secondary display
[ ] Region capture - small region
[ ] Region capture - cross-display
[ ] Window capture - standard window
[ ] Window capture - floating window
[ ] Window capture - fullscreen app

## Clipboard Tests
[ ] Paste in Messages
[ ] Paste in Slack
[ ] Paste in Mail
[ ] Paste in Notes
[ ] Paste in Finder (creates file)
[ ] Paste in Preview (New from Clipboard)

## Edge Cases
[ ] Capture during video playback
[ ] Capture of translucent window
[ ] Capture when display is mirrored
[ ] Capture with color profile mismatch
[ ] Rapid repeated captures
```

---

## Release Checklist

### Pre-Release

```
[ ] All unit tests pass
[ ] UI tests pass
[ ] Manual testing complete
[ ] Memory leaks checked (Instruments)
[ ] Performance targets met
[ ] Code signed correctly
[ ] Notarization successful
[ ] Version number updated
[ ] Release notes written
```

### Post-Release

```
[ ] Verify download works
[ ] Verify installation works
[ ] Verify Gatekeeper passes
[ ] Monitor crash reports
[ ] Monitor user feedback
[ ] Update documentation
```
