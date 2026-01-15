# Global Hotkey Support: Shotter

This document covers the implementation of system-wide keyboard shortcuts for the Shotter application.

---

## Overview

Global hotkeys allow users to trigger screenshot captures from anywhere in macOS, regardless of which app is focused. This is critical for a screenshot utility.

### API Options

| API | Pros | Cons |
|-----|------|------|
| **Carbon Events** | Works system-wide, reliable, well-documented | Deprecated (but still functional) |
| **CGEvent Tap** | Modern, powerful | Requires Accessibility permission |
| **NSEvent.addGlobalMonitor** | Modern, easy | Cannot intercept/consume events |
| **HotKey (SPM package)** | Clean Swift API, handles Carbon | Third-party dependency |

**Recommendation**: Use **Carbon Events** directly or the **HotKey** Swift package for cleaner code.

---

## Option 1: HotKey Package (Recommended)

### Installation

Add to your `Package.swift` or via Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/soffes/HotKey`
3. Add to your target

### HotkeyManager.swift (Using HotKey Package)

```swift
import Foundation
import HotKey
import Carbon.HIToolbox

enum HotkeyAction {
    case fullScreen
    case region
    case window
}

@MainActor
final class HotkeyManager: ObservableObject {
    // Published properties for UI binding
    @Published var fullScreenHotkey: HotkeyConfiguration
    @Published var regionHotkey: HotkeyConfiguration
    @Published var windowHotkey: HotkeyConfiguration

    // Internal hotkey references
    private var fullScreenHotKey: HotKey?
    private var regionHotKey: HotKey?
    private var windowHotKey: HotKey?

    // Action callbacks
    private var fullScreenAction: (() -> Void)?
    private var regionAction: (() -> Void)?
    private var windowAction: (() -> Void)?

    init() {
        // Load saved or use defaults
        fullScreenHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.fullScreenKey,
            default: .fullScreen
        )
        regionHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.regionKey,
            default: .region
        )
        windowHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.windowKey,
            default: .window
        )
    }

    // MARK: - Registration

    func register(
        config: HotkeyConfiguration,
        for action: HotkeyAction,
        handler: @escaping () -> Void
    ) {
        let key = Key(carbonKeyCode: config.keyCode)
        let modifiers = carbonToNSModifiers(config.modifiers)

        guard let key = key else {
            print("HotkeyManager: Invalid key code \(config.keyCode)")
            return
        }

        let hotKey = HotKey(key: key, modifiers: modifiers)

        hotKey.keyDownHandler = { [weak self] in
            DispatchQueue.main.async {
                handler()
            }
        }

        switch action {
        case .fullScreen:
            fullScreenHotKey = hotKey
            fullScreenAction = handler
        case .region:
            regionHotKey = hotKey
            regionAction = handler
        case .window:
            windowHotKey = hotKey
            windowAction = handler
        }

        print("HotkeyManager: Registered \(action) with \(config.displayString)")
    }

    func unregister(_ action: HotkeyAction) {
        switch action {
        case .fullScreen:
            fullScreenHotKey = nil
            fullScreenAction = nil
        case .region:
            regionHotKey = nil
            regionAction = nil
        case .window:
            windowHotKey = nil
            windowAction = nil
        }
    }

    func unregisterAll() {
        fullScreenHotKey = nil
        regionHotKey = nil
        windowHotKey = nil
        fullScreenAction = nil
        regionAction = nil
        windowAction = nil
    }

    // MARK: - Update Hotkeys

    func updateHotkey(for action: HotkeyAction, config: HotkeyConfiguration) {
        // Save to UserDefaults
        switch action {
        case .fullScreen:
            config.save(for: HotkeyConfiguration.fullScreenKey)
            fullScreenHotkey = config
            if let handler = fullScreenAction {
                unregister(.fullScreen)
                register(config: config, for: .fullScreen, handler: handler)
            }
        case .region:
            config.save(for: HotkeyConfiguration.regionKey)
            regionHotkey = config
            if let handler = regionAction {
                unregister(.region)
                register(config: config, for: .region, handler: handler)
            }
        case .window:
            config.save(for: HotkeyConfiguration.windowKey)
            windowHotkey = config
            if let handler = windowAction {
                unregister(.window)
                register(config: config, for: .window, handler: handler)
            }
        }
    }

    // MARK: - Helpers

    private func carbonToNSModifiers(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if carbonModifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }

        return flags
    }
}
```

---

## Option 2: Pure Carbon Events Implementation

If you prefer not to use external dependencies, here's a complete Carbon-based implementation.

### HotkeyManager.swift (Pure Carbon)

```swift
import Foundation
import Carbon.HIToolbox
import AppKit

// MARK: - Global Callback Context

private var hotkeyManagerInstance: HotkeyManager?

enum HotkeyAction: Int {
    case fullScreen = 1
    case region = 2
    case window = 3
}

@MainActor
final class HotkeyManager: ObservableObject {
    // Published properties for UI binding
    @Published var fullScreenHotkey: HotkeyConfiguration
    @Published var regionHotkey: HotkeyConfiguration
    @Published var windowHotkey: HotkeyConfiguration

    // Carbon hotkey references
    private var fullScreenHotKeyRef: EventHotKeyRef?
    private var regionHotKeyRef: EventHotKeyRef?
    private var windowHotKeyRef: EventHotKeyRef?

    // Action callbacks
    private var actions: [HotkeyAction: () -> Void] = [:]

    // Event handler reference
    private var eventHandlerRef: EventHandlerRef?

    init() {
        // Store instance for C callback
        hotkeyManagerInstance = self

        // Load saved or use defaults
        fullScreenHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.fullScreenKey,
            default: .fullScreen
        )
        regionHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.regionKey,
            default: .region
        )
        windowHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.windowKey,
            default: .window
        )

        // Install event handler
        installEventHandler()
    }

    deinit {
        unregisterAll()
        removeEventHandler()
        hotkeyManagerInstance = nil
    }

    // MARK: - Event Handler Installation

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let error = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard error == noErr else { return error }

            // Dispatch to main thread
            DispatchQueue.main.async {
                hotkeyManagerInstance?.handleHotkey(id: Int(hotKeyID.id))
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func removeEventHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - Hotkey Handling

    private func handleHotkey(id: Int) {
        guard let action = HotkeyAction(rawValue: id),
              let callback = actions[action] else {
            return
        }
        callback()
    }

    // MARK: - Registration

    func register(
        config: HotkeyConfiguration,
        for action: HotkeyAction,
        handler: @escaping () -> Void
    ) {
        // Store callback
        actions[action] = handler

        // Create hotkey ID
        var hotKeyID = EventHotKeyID(
            signature: OSType(0x5348_5452), // 'SHTR' in hex
            id: UInt32(action.rawValue)
        )

        // Convert Carbon modifiers to CGEvent modifiers
        var modifiers: UInt32 = 0
        if config.modifiers & UInt32(cmdKey) != 0 {
            modifiers |= UInt32(cmdKey)
        }
        if config.modifiers & UInt32(shiftKey) != 0 {
            modifiers |= UInt32(shiftKey)
        }
        if config.modifiers & UInt32(optionKey) != 0 {
            modifiers |= UInt32(optionKey)
        }
        if config.modifiers & UInt32(controlKey) != 0 {
            modifiers |= UInt32(controlKey)
        }

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("HotkeyManager: Failed to register \(action), error: \(status)")
            return
        }

        // Store reference for unregistration
        switch action {
        case .fullScreen:
            fullScreenHotKeyRef = hotKeyRef
        case .region:
            regionHotKeyRef = hotKeyRef
        case .window:
            windowHotKeyRef = hotKeyRef
        }

        print("HotkeyManager: Registered \(action) with \(config.displayString)")
    }

    func unregister(_ action: HotkeyAction) {
        let ref: EventHotKeyRef?

        switch action {
        case .fullScreen:
            ref = fullScreenHotKeyRef
            fullScreenHotKeyRef = nil
        case .region:
            ref = regionHotKeyRef
            regionHotKeyRef = nil
        case .window:
            ref = windowHotKeyRef
            windowHotKeyRef = nil
        }

        if let ref = ref {
            UnregisterEventHotKey(ref)
        }

        actions[action] = nil
    }

    func unregisterAll() {
        unregister(.fullScreen)
        unregister(.region)
        unregister(.window)
    }

    // MARK: - Update Hotkeys

    func updateHotkey(for action: HotkeyAction, config: HotkeyConfiguration) {
        // Store current callback
        let callback = actions[action]

        // Unregister current
        unregister(action)

        // Save new config
        switch action {
        case .fullScreen:
            config.save(for: HotkeyConfiguration.fullScreenKey)
            fullScreenHotkey = config
        case .region:
            config.save(for: HotkeyConfiguration.regionKey)
            regionHotkey = config
        case .window:
            config.save(for: HotkeyConfiguration.windowKey)
            windowHotkey = config
        }

        // Re-register with new config
        if let callback = callback {
            register(config: config, for: action, handler: callback)
        }
    }
}
```

---

## Key Code Reference

Common key codes for Carbon Events:

```swift
import Carbon.HIToolbox

// Numbers
let kVK_ANSI_0: Int = 0x1D
let kVK_ANSI_1: Int = 0x12
let kVK_ANSI_2: Int = 0x13
let kVK_ANSI_3: Int = 0x14
let kVK_ANSI_4: Int = 0x15
let kVK_ANSI_5: Int = 0x17
let kVK_ANSI_6: Int = 0x16
let kVK_ANSI_7: Int = 0x1A
let kVK_ANSI_8: Int = 0x1C
let kVK_ANSI_9: Int = 0x19

// Letters (common ones for shortcuts)
let kVK_ANSI_A: Int = 0x00
let kVK_ANSI_C: Int = 0x08
let kVK_ANSI_S: Int = 0x01
let kVK_ANSI_X: Int = 0x07
let kVK_ANSI_Z: Int = 0x06

// Special keys
let kVK_Space: Int = 0x31
let kVK_Return: Int = 0x24
let kVK_Tab: Int = 0x30
let kVK_Escape: Int = 0x35
let kVK_Delete: Int = 0x33

// Function keys
let kVK_F1: Int = 0x7A
let kVK_F2: Int = 0x78
let kVK_F3: Int = 0x63
let kVK_F4: Int = 0x76

// Modifiers (as masks)
let cmdKey: Int = 1 << 8      // 256
let shiftKey: Int = 1 << 9    // 512
let optionKey: Int = 1 << 11  // 2048
let controlKey: Int = 1 << 12 // 4096
```

---

## Hotkey Recorder View

A SwiftUI view for capturing custom hotkey combinations:

### HotkeyRecorderView.swift

```swift
import SwiftUI
import Carbon.HIToolbox

struct HotkeyRecorderView: View {
    @Binding var configuration: HotkeyConfiguration
    let onConfigurationChanged: (HotkeyConfiguration) -> Void

    @State private var isRecording = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Button(action: startRecording) {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Press shortcut...")
                            .foregroundColor(.secondary)
                    } else {
                        Text(configuration.displayString)
                    }
                }
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .onKeyPress { keyPress in
                if isRecording {
                    handleKeyPress(keyPress)
                    return .handled
                }
                return .ignored
            }

            if !isRecording {
                Button(action: clearHotkey) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        isFocused = true
    }

    private func handleKeyPress(_ keyPress: KeyPress) {
        // Escape cancels recording
        if keyPress.key == .escape {
            isRecording = false
            return
        }

        // Build new configuration from key press
        let modifiers = keyPress.modifiers
        var carbonModifiers: UInt32 = 0

        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        // Require at least one modifier
        guard carbonModifiers != 0 else { return }

        // Get key code (this is simplified - real implementation needs key code mapping)
        let keyCode = keyCodeFromCharacter(keyPress.key.character)

        let newConfig = HotkeyConfiguration(
            keyCode: keyCode,
            modifiers: carbonModifiers
        )

        configuration = newConfig
        onConfigurationChanged(newConfig)
        isRecording = false
    }

    private func clearHotkey() {
        // Set to a disabled/empty state
        let emptyConfig = HotkeyConfiguration(keyCode: 0, modifiers: 0)
        configuration = emptyConfig
        onConfigurationChanged(emptyConfig)
    }

    private func keyCodeFromCharacter(_ character: Character) -> UInt32 {
        let keyMap: [Character: UInt32] = [
            "0": UInt32(kVK_ANSI_0),
            "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4),
            "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "a": UInt32(kVK_ANSI_A),
            "A": UInt32(kVK_ANSI_A),
            "c": UInt32(kVK_ANSI_C),
            "C": UInt32(kVK_ANSI_C),
            "s": UInt32(kVK_ANSI_S),
            "S": UInt32(kVK_ANSI_S),
            "x": UInt32(kVK_ANSI_X),
            "X": UInt32(kVK_ANSI_X),
            "z": UInt32(kVK_ANSI_Z),
            "Z": UInt32(kVK_ANSI_Z),
        ]
        return keyMap[character] ?? 0
    }
}

// MARK: - Usage Example

struct HotkeyPreferencesExample: View {
    @State private var fullScreenConfig = HotkeyConfiguration.fullScreen
    @State private var regionConfig = HotkeyConfiguration.region

    var body: some View {
        Form {
            LabeledContent("Full Screen") {
                HotkeyRecorderView(configuration: $fullScreenConfig) { newConfig in
                    print("Full screen hotkey changed to: \(newConfig.displayString)")
                }
            }

            LabeledContent("Region") {
                HotkeyRecorderView(configuration: $regionConfig) { newConfig in
                    print("Region hotkey changed to: \(newConfig.displayString)")
                }
            }
        }
        .padding()
    }
}
```

---

## Alternative: NSEvent Global Monitor

For simpler monitoring (cannot consume events, but can observe them):

```swift
import AppKit

final class GlobalEventMonitor {
    private var monitor: Any?

    func startMonitoring(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            handler(event)
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// Usage
let eventMonitor = GlobalEventMonitor()

eventMonitor.startMonitoring(matching: .keyDown) { event in
    // Check for Cmd+Shift+3
    if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 20 {
        print("Cmd+Shift+3 detected")
        // Note: This doesn't prevent the system screenshot from triggering
    }
}
```

**Limitation**: `NSEvent.addGlobalMonitorForEvents` cannot intercept or consume events. The system will still process them. This approach is only useful for observing, not for creating exclusive hotkeys.

---

## Conflict with System Shortcuts

### Default Screenshot Shortcuts

macOS reserves these shortcuts by default:
- `Cmd+Shift+3` - Full screen screenshot (saves to disk)
- `Cmd+Shift+4` - Region selection (saves to disk)
- `Cmd+Shift+5` - Screenshot/recording panel
- `Cmd+Ctrl+Shift+3` - Full screen to clipboard
- `Cmd+Ctrl+Shift+4` - Region to clipboard

### Recommendations

**Option A**: Use different shortcuts
- `Cmd+Shift+1` / `Cmd+Shift+2` for Shotter
- `Ctrl+Shift+3` / `Ctrl+Shift+4`
- `Option+Shift+3` / `Option+Shift+4`

**Option B**: Disable system shortcuts
Instruct users to disable in System Settings → Keyboard → Shortcuts → Screenshots

**Option C**: Override (Advanced)
With Accessibility permission, you can use CGEvent taps to intercept and consume system shortcuts:

```swift
import CoreGraphics

func createEventTap() -> CFMachPort? {
    let eventMask = (1 << CGEventType.keyDown.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { proxy, type, event, refcon in
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Check for Cmd+Shift+3
            if keyCode == 20 && flags.contains([.maskCommand, .maskShift]) {
                // Handle the event ourselves
                DispatchQueue.main.async {
                    // Trigger our capture
                }
                return nil // Consume the event
            }

            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    ) else {
        return nil
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    return tap
}
```

**Note**: Event taps require the Accessibility permission and the app must not be sandboxed.

---

## Testing Hotkeys

### Manual Testing Checklist

```
[ ] Hotkey works when app is in background
[ ] Hotkey works when app is not focused
[ ] Hotkey works from fullscreen apps
[ ] Hotkey triggers correct capture mode
[ ] Multiple hotkeys can be registered simultaneously
[ ] Changing hotkey in preferences takes effect immediately
[ ] Hotkeys persist after app restart
[ ] Conflicting hotkeys show appropriate warning
[ ] Disabled hotkeys don't trigger
```

### Debug Logging

Add logging to verify hotkey registration:

```swift
func register(config: HotkeyConfiguration, for action: HotkeyAction, handler: @escaping () -> Void) {
    print("HotkeyManager: Attempting to register \(action)")
    print("  - Key code: \(config.keyCode)")
    print("  - Modifiers: \(config.modifiers)")

    // ... registration code ...

    if status == noErr {
        print("HotkeyManager: Successfully registered \(action)")
    } else {
        print("HotkeyManager: Failed to register \(action), error: \(status)")
    }
}
```
