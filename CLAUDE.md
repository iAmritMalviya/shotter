# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project (requires XcodeGen)
xcodegen generate

# Build via command line
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Debug build

# Build for release
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release build
```

## Architecture

macOS menu bar screenshot utility using SwiftUI + AppKit hybrid approach:

- **ScreenCaptureKit** (macOS 12.3+) for screen capture
- **Carbon Events** for global hotkeys
- **NSPasteboard** for clipboard operations
- **LSUIElement** for menu-bar-only app (no Dock icon)

Key files:
- `Shotter/Services/ScreenCaptureService.swift` - Core capture logic
- `Shotter/Services/HotkeyManager.swift` - Global keyboard shortcuts
- `Shotter/Controllers/MenuBarController.swift` - Menu bar UI

## Workflow

After completing each prompt/task, commit and push all changes to git.

Do not add co-author lines to commits.
