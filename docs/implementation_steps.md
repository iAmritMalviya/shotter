# Implementation Steps: Shotter

This document provides a complete step-by-step guide to implementing the Shotter macOS application from scratch.

---

## Phase 1: Xcode Project Setup

### Step 1.1: Create New Xcode Project

1. Open Xcode 15+ (or latest version)
2. File → New → Project
3. Select **macOS** → **App**
4. Configure project:
   - **Product Name**: `Shotter`
   - **Team**: Select your Apple Developer account
   - **Organization Identifier**: `com.yourname` (e.g., `com.amrit`)
   - **Bundle Identifier**: Auto-fills as `com.amrit.Shotter`
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
   - **Storage**: `None`
   - **Include Tests**: Uncheck (optional for MVP)
5. Click **Create** and save to `/Users/amrit/code/shotter/`

### Step 1.2: Configure as Menu Bar App

Edit `Info.plist` to make the app run in the menu bar without a Dock icon:

1. Open `Shotter/Info.plist` in Xcode
2. Add a new row:
   - **Key**: `Application is agent (UIElement)`
   - **Type**: Boolean
   - **Value**: `YES`

Alternatively, add directly to the plist source:

```xml
<key>LSUIElement</key>
<true/>
```

### Step 1.3: Set Deployment Target

1. Select the **Shotter** project in the navigator
2. Select the **Shotter** target
3. Go to **General** tab
4. Set **Minimum Deployments** → **macOS 12.3** (for ScreenCaptureKit)

### Step 1.4: Add App Icon

1. Open `Assets.xcassets`
2. Create a new **Image Set** named `MenuBarIcon`
3. Add 18x18 (1x) and 36x36 (2x) PNG icons
4. Set **Render As** to `Template Image` for proper menu bar appearance

---

## Phase 2: Project Structure Setup

### Step 2.1: Create Folder Structure

In Xcode, create the following groups (right-click → New Group):

```
Shotter/
├── App/
├── Controllers/
├── Services/
├── Views/
├── Models/
└── Resources/
```

### Step 2.2: Create Swift Files

Create the following empty Swift files in their respective groups:

**App/**
- `AppDelegate.swift`

**Controllers/**
- `MenuBarController.swift`

**Services/**
- `ScreenCaptureService.swift`
- `ClipboardManager.swift`
- `HotkeyManager.swift`
- `PermissionManager.swift`

**Views/**
- `PreferencesView.swift`
- `RegionSelectionWindow.swift`

**Models/**
- `CaptureMode.swift`
- `HotkeyConfiguration.swift`

---

## Phase 3: Core Implementation Order

Follow this implementation order for logical dependency resolution:

### Step 3.1: Models (No Dependencies)

Implement these first as they have no dependencies:

1. **CaptureMode.swift** - Enum for capture types
2. **HotkeyConfiguration.swift** - Struct for hotkey storage

### Step 3.2: Clipboard Manager (Foundation Only)

Implement `ClipboardManager.swift`:
- Simple NSPasteboard wrapper
- No external dependencies
- Can be tested immediately

### Step 3.3: Permission Manager

Implement `PermissionManager.swift`:
- Check ScreenCaptureKit permission status
- Request permission when needed
- Provide status updates via Combine/async

### Step 3.4: Screen Capture Service

Implement `ScreenCaptureService.swift`:
- Depends on: PermissionManager
- Primary: ScreenCaptureKit implementation
- Fallback: CGWindowListCreateImage

### Step 3.5: Hotkey Manager

Implement `HotkeyManager.swift`:
- Depends on: HotkeyConfiguration
- Register global shortcuts
- Trigger capture actions

### Step 3.6: Views

Implement UI components:
1. **PreferencesView.swift** - Settings UI
2. **RegionSelectionWindow.swift** - Selection overlay

### Step 3.7: Menu Bar Controller

Implement `MenuBarController.swift`:
- Depends on: All services
- Creates status item
- Wires up menu actions

### Step 3.8: App Delegate & Entry Point

Implement `AppDelegate.swift`:
- Initialize all services
- Set up menu bar controller
- Handle app lifecycle

Update `ShotterApp.swift`:
- Connect AppDelegate
- Configure SwiftUI app lifecycle

---

## Phase 4: Detailed Implementation Checklist

### 4.1: CaptureMode.swift

```
[ ] Create CaptureMode enum with cases: fullScreen, region, window
[ ] Add associated values for region (CGRect) and window (CGWindowID)
[ ] Implement CustomStringConvertible for menu labels
```

### 4.2: HotkeyConfiguration.swift

```
[ ] Create struct with keyCode and modifiers properties
[ ] Add Codable conformance for UserDefaults storage
[ ] Define default hotkey (Cmd+Shift+5 or custom)
[ ] Add static presets for common shortcuts
```

### 4.3: ClipboardManager.swift

```
[ ] Create ClipboardManager class
[ ] Implement copy(image: NSImage) -> Bool method
[ ] Clear existing clipboard before copying
[ ] Write image as both PNG and TIFF for compatibility
[ ] Add error handling for clipboard write failures
```

### 4.4: PermissionManager.swift

```
[ ] Create PermissionManager class (ObservableObject)
[ ] Add @Published isAuthorized property
[ ] Implement checkPermission() async method
[ ] Implement requestPermission() method (opens System Preferences)
[ ] Add permission status observer for real-time updates
[ ] Handle CGPreflightScreenCaptureAccess() for legacy check
```

### 4.5: ScreenCaptureService.swift

```
[ ] Create ScreenCaptureService class
[ ] Inject PermissionManager dependency
[ ] Implement captureFullScreen() async throws -> NSImage
[ ] Implement captureRegion(rect: CGRect) async throws -> NSImage
[ ] Implement captureWindow(windowID: CGWindowID) async throws -> NSImage
[ ] Use SCShareableContent to enumerate displays/windows
[ ] Use SCStream for capture (no file output)
[ ] Convert CMSampleBuffer to NSImage in memory
[ ] Add legacy fallback using CGWindowListCreateImage
[ ] Define custom errors (CaptureError enum)
```

### 4.6: HotkeyManager.swift

```
[ ] Create HotkeyManager class
[ ] Add dependency on Carbon framework
[ ] Implement registerHotkey(config: HotkeyConfiguration, action: () -> Void)
[ ] Implement unregisterHotkey()
[ ] Store EventHotKeyRef for cleanup
[ ] Create global event handler function
[ ] Load/save configuration from UserDefaults
[ ] Support multiple hotkeys (full screen, region, window)
```

### 4.7: RegionSelectionWindow.swift

```
[ ] Create RegionSelectionWindow (NSWindow subclass)
[ ] Configure as borderless, transparent, full-screen overlay
[ ] Set window level above everything (.screenSaver)
[ ] Implement mouse event handling (down, dragged, up)
[ ] Draw selection rectangle with dashed border
[ ] Show dimensions tooltip while dragging
[ ] Handle Escape key to cancel
[ ] Return selected CGRect via callback/async
```

### 4.8: PreferencesView.swift

```
[ ] Create PreferencesView (SwiftUI View)
[ ] Add hotkey recorder UI (KeyboardShortcuts-style)
[ ] Add "Launch at Login" toggle (use SMAppService)
[ ] Add default capture mode picker
[ ] Add "Show notification after capture" toggle
[ ] Style with Form and Section
[ ] Add "About" section with version info
```

### 4.9: MenuBarController.swift

```
[ ] Create MenuBarController class (ObservableObject)
[ ] Create NSStatusItem with variable length
[ ] Set button image from Assets (template image)
[ ] Build NSMenu with items:
    - Capture Full Screen (⌘⇧3)
    - Capture Region (⌘⇧4)
    - Capture Window (⌘⇧5)
    - Separator
    - Preferences... (⌘,)
    - Separator
    - Quit Shotter (⌘Q)
[ ] Connect menu actions to capture service
[ ] Handle async capture with visual feedback
[ ] Show error alerts when capture fails
```

### 4.10: AppDelegate.swift

```
[ ] Create AppDelegate class (NSApplicationDelegate)
[ ] Initialize all service instances
[ ] Set up MenuBarController
[ ] Register global hotkeys on applicationDidFinishLaunching
[ ] Unregister hotkeys on applicationWillTerminate
[ ] Handle permission prompts on first launch
```

### 4.11: ShotterApp.swift

```
[ ] Modify ShotterApp to use @NSApplicationDelegateAdaptor
[ ] Remove default WindowGroup (menu bar only)
[ ] Add Settings scene for preferences window
```

---

## Phase 5: Testing Checklist

### 5.1: Unit Tests

```
[ ] Test ClipboardManager.copy() writes to pasteboard
[ ] Test ClipboardManager handles nil/invalid images
[ ] Test HotkeyConfiguration encoding/decoding
[ ] Test CaptureMode enum completeness
```

### 5.2: Integration Tests

```
[ ] Test full capture flow: hotkey → capture → clipboard
[ ] Test region selection returns correct coordinates
[ ] Test permission denied shows appropriate error
[ ] Test menu actions trigger correct capture modes
```

### 5.3: Manual Testing

```
[ ] Verify app appears in menu bar only (no Dock icon)
[ ] Test global hotkey works when app is not focused
[ ] Test capture works across multiple displays
[ ] Test captured image pastes correctly in:
    - Messages
    - Slack
    - Mail
    - Preview (Cmd+N → Cmd+V)
    - Finder (as file)
[ ] Test region selection cancellation (Escape)
[ ] Test preferences window opens/closes correctly
[ ] Test quit functionality
```

---

## Phase 6: Build & Distribution

### 6.1: Development Build

```
[ ] Build runs without errors
[ ] All compiler warnings resolved
[ ] Debug builds work on both Apple Silicon and Intel
```

### 6.2: Release Configuration

```
[ ] Switch to Release scheme
[ ] Verify optimization flags
[ ] Strip debug symbols
[ ] Set correct version and build numbers
```

### 6.3: Code Signing

```
[ ] Select valid Developer ID certificate
[ ] Configure automatic signing or manual provisioning
[ ] Verify entitlements are correct
```

### 6.4: Notarization

```
[ ] Archive the app (Product → Archive)
[ ] Submit to Apple for notarization
[ ] Wait for approval (usually < 15 minutes)
[ ] Staple notarization ticket to app
```

### 6.5: Distribution

```
[ ] Create DMG or ZIP for distribution
[ ] Test installation on clean macOS system
[ ] Verify Gatekeeper allows execution
[ ] Test first-launch permission flow
```

---

## Phase 7: Build Commands Reference

### Xcode Command Line

```bash
# Build for debugging
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Debug build

# Build for release
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release build

# Build universal binary
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release \
  -arch arm64 -arch x86_64 build

# Archive for distribution
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release \
  -archivePath ./build/Shotter.xcarchive archive

# Export from archive
xcodebuild -exportArchive -archivePath ./build/Shotter.xcarchive \
  -exportPath ./build/export -exportOptionsPlist ExportOptions.plist
```

### Notarization Commands

```bash
# Notarize app (requires app-specific password)
xcrun notarytool submit Shotter.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple notarization ticket
xcrun stapler staple Shotter.app

# Verify notarization
spctl -a -vvv -t install Shotter.app
```

---

## Quick Start Summary

For a minimal working version, implement in this exact order:

1. **Create Xcode project** with LSUIElement=YES
2. **ClipboardManager** - Copy NSImage to pasteboard
3. **ScreenCaptureService** - Capture screen to NSImage (full screen only first)
4. **MenuBarController** - Status item with one "Capture" button
5. **AppDelegate** - Wire everything together
6. **Test** - Click menu item → Image appears in clipboard

Then iterate to add:
- Region selection
- Window selection
- Global hotkeys
- Preferences UI
- Permission handling improvements
