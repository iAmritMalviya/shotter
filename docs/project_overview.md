# Project Overview: Shotter

## Application Summary

**Shotter** is a lightweight macOS menu bar utility that captures screenshots and copies them directly to the system clipboard without saving any files to disk. Users can then paste the captured image anywhere using `Cmd + V`.

---

## Problem Statement

The default macOS screenshot workflow has unnecessary friction:

1. Press screenshot shortcut → Image saves to Desktop/folder
2. Locate the saved file
3. Open or select the file
4. Copy to clipboard (`Cmd + C`)
5. Delete the file to avoid clutter

**Shotter eliminates steps 2-5**, providing a single-action capture-to-clipboard workflow.

---

## Core Requirements

| Requirement | Description |
|-------------|-------------|
| **No Disk Storage** | Screenshots must never touch the filesystem |
| **Clipboard Integration** | Captured images are immediately available for `Cmd + V` |
| **Menu Bar App** | Lives in the menu bar, no Dock icon |
| **Global Hotkey** | Configurable keyboard shortcut (default: `Cmd + Shift + 4`) |
| **Permission Handling** | Graceful handling of Screen Recording permission |
| **Capture Modes** | Full screen, selected region, specific window |
| **Visual Feedback** | Brief confirmation when capture succeeds |

---

## Technical Architecture

### Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **UI Framework** | SwiftUI + AppKit | SwiftUI for preferences; AppKit for menu bar integration |
| **Screen Capture** | ScreenCaptureKit (macOS 12.3+) | Modern Apple API, handles permissions gracefully |
| **Fallback Capture** | CGWindowListCreateImage | Legacy support for older macOS versions |
| **Global Hotkeys** | Carbon Events / HotKey library | System-wide keyboard shortcuts |
| **Clipboard** | NSPasteboard | Standard macOS clipboard API |
| **Storage** | UserDefaults | Hotkey preferences only |

### Minimum System Requirements

- **macOS Version**: 12.3 (Monterey) for ScreenCaptureKit, 11.0 for fallback
- **Architecture**: Universal (Apple Silicon + Intel)
- **Permissions**: Screen Recording

---

## Application Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Shotter App                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   App Entry  │    │  Menu Bar    │    │  Preferences │       │
│  │   Point      │───▶│  Controller  │◀──▶│  Window      │       │
│  │  (main.swift)│    │              │    │  (SwiftUI)   │       │
│  └──────────────┘    └──────┬───────┘    └──────────────┘       │
│                             │                                    │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────┐       │
│  │                  Core Services                        │       │
│  ├──────────────┬──────────────┬──────────────┐         │       │
│  │   Hotkey     │   Screen     │  Clipboard   │         │       │
│  │   Manager    │   Capture    │  Manager     │         │       │
│  │              │   Service    │              │         │       │
│  └──────┬───────┴──────┬───────┴──────┬───────┘         │       │
│         │              │              │                  │       │
│         ▼              ▼              ▼                  │       │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │       │
│  │ Carbon/CGEvent│ │ScreenCapture │ │ NSPasteboard │     │       │
│  │    APIs      │ │    Kit       │ │              │     │       │
│  └──────────────┘ └──────────────┘ └──────────────┘     │       │
│                                                          │       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. App Entry Point (`ShotterApp.swift`)

- Initialize app as menu bar only (LSUIElement)
- Set up AppDelegate for lifecycle management
- Initialize core services

### 2. Menu Bar Controller (`MenuBarController.swift`)

- Create and manage NSStatusItem
- Build dropdown menu with capture options
- Handle menu item actions
- Show/hide preferences window

### 3. Screen Capture Service (`ScreenCaptureService.swift`)

- **Primary**: ScreenCaptureKit for modern capture
- **Fallback**: CGWindowListCreateImage for legacy support
- Capture modes:
  - `captureFullScreen()` - All displays
  - `captureRegion(rect: CGRect)` - User-selected area
  - `captureWindow(windowID: CGWindowID)` - Specific window
- Returns `NSImage` directly (no disk I/O)

### 4. Region Selection Overlay (`RegionSelectionWindow.swift`)

- Full-screen transparent window
- Mouse drag to select region
- Visual feedback (selection rectangle)
- Keyboard support (Escape to cancel)

### 5. Clipboard Manager (`ClipboardManager.swift`)

- Copy `NSImage` to `NSPasteboard`
- Support multiple image formats (PNG, TIFF)
- Clear previous clipboard contents

### 6. Hotkey Manager (`HotkeyManager.swift`)

- Register global keyboard shortcuts
- Handle hotkey events
- Support customizable key combinations
- Persist preferences to UserDefaults

### 7. Preferences Window (`PreferencesView.swift`)

- SwiftUI-based settings UI
- Hotkey configuration
- Launch at login toggle
- Capture mode defaults

### 8. Permission Handler (`PermissionManager.swift`)

- Check Screen Recording permission status
- Prompt user for permission
- Handle permission denied state
- Provide guidance to System Preferences

---

## Data Flow

### Screenshot Capture Flow

```
User Action (Hotkey/Menu Click)
         │
         ▼
┌─────────────────────┐
│ Check Screen        │
│ Recording Permission│
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │ Granted?  │
    └─────┬─────┘
      No  │  Yes
      │   │
      ▼   ▼
┌─────────┐  ┌─────────────────┐
│ Show    │  │ Determine       │
│ Alert   │  │ Capture Mode    │
└─────────┘  └────────┬────────┘
                      │
         ┌────────────┼────────────┐
         ▼            ▼            ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ Full    │ │ Region  │ │ Window  │
    │ Screen  │ │ Select  │ │ Select  │
    └────┬────┘ └────┬────┘ └────┬────┘
         │           │           │
         └───────────┼───────────┘
                     ▼
         ┌─────────────────────┐
         │ ScreenCaptureKit    │
         │ Capture to NSImage  │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │ NSPasteboard        │
         │ Copy Image          │
         └──────────┬──────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │ Visual Feedback     │
         │ (Brief notification)│
         └─────────────────────┘
```

---

## File Structure

```
Shotter/
├── Shotter.xcodeproj
├── Shotter/
│   ├── ShotterApp.swift              # App entry point
│   ├── AppDelegate.swift             # AppKit lifecycle
│   ├── Info.plist                    # App configuration
│   ├── Shotter.entitlements          # Sandbox entitlements
│   │
│   ├── Controllers/
│   │   └── MenuBarController.swift   # Status bar management
│   │
│   ├── Services/
│   │   ├── ScreenCaptureService.swift
│   │   ├── ClipboardManager.swift
│   │   ├── HotkeyManager.swift
│   │   └── PermissionManager.swift
│   │
│   ├── Views/
│   │   ├── PreferencesView.swift     # Settings UI
│   │   ├── RegionSelectionWindow.swift
│   │   └── NotificationView.swift    # Capture feedback
│   │
│   ├── Models/
│   │   ├── CaptureMode.swift
│   │   └── HotkeyConfiguration.swift
│   │
│   └── Resources/
│       └── Assets.xcassets           # Menu bar icons
│
└── README.md
```

---

## Key Design Decisions

### 1. Menu Bar Only (No Dock Icon)

The app sets `LSUIElement = YES` in Info.plist to run as a background utility without a Dock presence. This matches user expectations for a quick-access tool.

### 2. ScreenCaptureKit as Primary API

ScreenCaptureKit (introduced macOS 12.3) is Apple's modern screen capture framework:
- Better performance than legacy APIs
- Handles HDR content correctly
- Integrates with system permission prompts
- Supports all capture modes natively

### 3. No Disk I/O

The entire capture pipeline operates in memory:
- `SCStreamOutput` → `CMSampleBuffer` → `CGImage` → `NSImage` → `NSPasteboard`
- No temporary files, no cleanup required

### 4. Global Hotkeys via Carbon Events

While Carbon is deprecated, it remains the only reliable way to register global hotkeys on macOS. We use a minimal wrapper to register shortcuts that work even when the app is not focused.

### 5. SwiftUI + AppKit Hybrid

- **SwiftUI**: Modern declarative UI for preferences window
- **AppKit**: Required for NSStatusItem, NSWindow (region selection), NSPasteboard

---

## Security Considerations

| Aspect | Implementation |
|--------|----------------|
| **Screen Recording** | Required permission, cannot be bypassed |
| **Sandboxing** | Disabled (screen capture requires it) |
| **Code Signing** | Required for distribution and permissions |
| **Hardened Runtime** | Enabled for notarization |
| **No Network** | App operates entirely offline |
| **No File Access** | No documents, no temp files |

---

## Success Metrics

1. **Capture Speed**: < 100ms from hotkey to clipboard
2. **Memory Usage**: < 50MB idle, < 150MB during capture
3. **Reliability**: 100% capture success when permission granted
4. **User Experience**: Zero-configuration default operation
