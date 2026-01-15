# Shotter

A lightweight macOS menu bar utility that captures screenshots and copies them directly to the clipboard - no files saved to disk.

## Features

- **Capture Full Screen** - `Cmd+Shift+3`
- **Capture Region** - `Cmd+Shift+4` (drag to select)
- **Capture Window** - `Cmd+Shift+5` (choose from list)
- **Menu Bar App** - Lives in your menu bar, no Dock icon
- **Global Hotkeys** - Works from any application
- **Zero Disk Usage** - Images go straight to clipboard

## Requirements

- macOS 12.3 (Monterey) or later
- Xcode 15+ for building
- Screen Recording permission

## Quick Start

### Option 1: Using XcodeGen (Recommended)

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate Xcode project
cd /Users/amrit/code/shotter
xcodegen generate

# Open in Xcode
open Shotter.xcodeproj
```

### Option 2: Manual Xcode Setup

1. Open Xcode
2. Create new macOS App project named "Shotter"
3. Delete the generated Swift files
4. Drag the `Shotter/` folder into the project
5. Configure signing & entitlements (see below)

## Build & Run

1. Open `Shotter.xcodeproj` in Xcode
2. Select your Development Team in Signing & Capabilities
3. Press `Cmd+R` to build and run
4. Grant Screen Recording permission when prompted

## First Run

1. App appears in menu bar (camera icon)
2. Click the icon → "Grant Screen Recording Permission"
3. Enable Shotter in System Settings
4. Restart Shotter if needed
5. Use `Cmd+Shift+3` to capture!

## Project Structure

```
Shotter/
├── ShotterApp.swift          # App entry point
├── AppDelegate.swift         # Lifecycle & hotkey setup
├── Info.plist                # App configuration
├── Shotter.entitlements      # Sandbox settings
├── Controllers/
│   └── MenuBarController.swift
├── Services/
│   ├── ScreenCaptureService.swift
│   ├── ClipboardManager.swift
│   ├── HotkeyManager.swift
│   └── PermissionManager.swift
├── Views/
│   ├── PreferencesView.swift
│   └── RegionSelectionWindow.swift
├── Models/
│   ├── CaptureMode.swift
│   ├── CaptureError.swift
│   └── HotkeyConfiguration.swift
└── Resources/
    └── Assets.xcassets/
```

## Signing Configuration

In Xcode → Signing & Capabilities:

1. **Team**: Select your Apple Developer account
2. **Bundle Identifier**: `com.yourname.Shotter`
3. **Signing Certificate**: "Sign to Run Locally" or "Development"
4. **Hardened Runtime**: Enabled
5. **Sandbox**: Disabled (required for screen capture)

## Troubleshooting

### "Screen Recording permission required"

1. Open System Settings → Privacy & Security → Screen Recording
2. Find Shotter and toggle ON
3. Restart Shotter

### Hotkeys not working

Default hotkeys (`Cmd+Shift+3/4/5`) may conflict with system screenshots.
Either:
- Disable system screenshots in System Settings → Keyboard → Shortcuts
- Or Shotter will still work, but system screenshot will also trigger

### App not appearing in menu bar

Check Info.plist has `LSUIElement = YES`

## License

MIT
