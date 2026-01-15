# Permissions and Entitlements: Shotter

This document covers macOS permissions, entitlements, code signing, and sandboxing configuration for the Shotter application.

---

## Required Permissions

### Screen Recording Permission

**Purpose**: Required to capture screen contents using ScreenCaptureKit or CGWindowListCreateImage.

**How it works**:
1. First capture attempt triggers system permission dialog
2. User must explicitly grant permission in System Settings
3. App needs to be restarted to activate permission (in some cases)

**API Behavior**:
- `SCShareableContent.excludingDesktopWindows()` - Triggers permission prompt, returns empty/error if denied
- `CGPreflightScreenCaptureAccess()` - Returns `false` if permission not granted
- `CGRequestScreenCaptureAccess()` - Triggers permission prompt

**No Info.plist entry required** - Screen Recording permission is handled entirely at runtime.

### Accessibility Permission (Optional)

**Purpose**: Only required if using CGEvent taps to intercept and consume keyboard events.

**When needed**:
- If you want to override system screenshot shortcuts
- If using event taps instead of Carbon hotkeys

**If using standard Carbon hotkeys**: Accessibility permission is **NOT** required.

---

## Entitlements Configuration

### Shotter.entitlements

Create this file in your Xcode project:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime exceptions -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>

    <!-- Required for notarization -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>

    <!-- App Sandbox - MUST be disabled for screen capture -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

### Why Sandboxing Must Be Disabled

Screen capture APIs require direct access to system graphics:

| Feature | Sandbox Compatible | Notes |
|---------|-------------------|-------|
| ScreenCaptureKit | No | Requires system-level access |
| CGWindowListCreateImage | No | Requires system-level access |
| CGDisplayCreateImage | No | Requires system-level access |
| NSPasteboard (write) | Yes | Works in sandbox |
| Global Hotkeys | No | Carbon events require system access |

**Bottom line**: A screenshot utility cannot be sandboxed.

---

## Info.plist Configuration

### Complete Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Basic app identity -->
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>

    <!-- Menu bar app (no Dock icon) -->
    <key>LSUIElement</key>
    <true/>

    <!-- Minimum macOS version -->
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>

    <!-- App category -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>

    <!-- Principal class for AppKit integration -->
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>

    <!-- High resolution capable -->
    <key>NSHighResolutionCapable</key>
    <true/>

    <!-- Support for Apple Silicon and Intel -->
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
</dict>
</plist>
```

### Key Info.plist Entries Explained

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | Makes app menu-bar only (no Dock icon) |
| `LSMinimumSystemVersion` | `12.3` | Requires macOS Monterey for ScreenCaptureKit |
| `LSApplicationCategoryType` | `public.app-category.utilities` | App Store category |
| `NSHighResolutionCapable` | `true` | Enables Retina display support |

---

## Code Signing

### Development Signing

For local development, Xcode's automatic signing works:

1. Select your project in Xcode
2. Go to **Signing & Capabilities** tab
3. Check **Automatically manage signing**
4. Select your **Team** (Apple Developer account)

### Distribution Signing

For distribution outside the App Store, you need a Developer ID certificate:

1. **Developer ID Application** certificate for the app itself
2. **Developer ID Installer** certificate (if using .pkg)

#### Export Options

Create `ExportOptions.plist` for command-line builds:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

---

## Notarization

Notarization is required for apps distributed outside the App Store to avoid Gatekeeper warnings.

### Prerequisites

1. Apple Developer Program membership
2. Developer ID Application certificate
3. App-specific password for your Apple ID

### Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → Security → App-Specific Passwords
3. Generate a password, name it "Notarization"
4. Store in Keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Notarization Process

#### Step 1: Archive the App

```bash
xcodebuild -project Shotter.xcodeproj \
  -scheme Shotter \
  -configuration Release \
  -archivePath ./build/Shotter.xcarchive \
  archive
```

#### Step 2: Export the Archive

```bash
xcodebuild -exportArchive \
  -archivePath ./build/Shotter.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist
```

#### Step 3: Create ZIP for Notarization

```bash
cd ./build/export
ditto -c -k --keepParent Shotter.app Shotter.zip
```

#### Step 4: Submit for Notarization

```bash
xcrun notarytool submit Shotter.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait
```

The `--wait` flag blocks until notarization completes (usually 5-15 minutes).

#### Step 5: Staple the Ticket

```bash
xcrun stapler staple Shotter.app
```

#### Step 6: Verify

```bash
# Verify code signature
codesign -vvv --deep --strict Shotter.app

# Verify notarization
spctl -a -vvv -t install Shotter.app
```

Expected output:
```
Shotter.app: accepted
source=Notarized Developer ID
```

---

## Handling Permission Flow

### First Launch Experience

```swift
import SwiftUI
import ScreenCaptureKit

struct FirstLaunchView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var showingPermissionGuide = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to Shotter")
                .font(.title)

            Text("Shotter needs Screen Recording permission to capture screenshots.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if permissionManager.isAuthorized {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Button("Start Using Shotter") {
                    // Dismiss onboarding
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Grant Permission") {
                    Task {
                        await permissionManager.requestPermission()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("How to Enable") {
                    showingPermissionGuide = true
                }
                .buttonStyle(.link)
            }
        }
        .padding(40)
        .frame(width: 400, height: 350)
        .sheet(isPresented: $showingPermissionGuide) {
            PermissionGuideView()
        }
    }
}

struct PermissionGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to Enable Screen Recording")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("1.")
                        .fontWeight(.bold)
                    Text("Open **System Settings** → **Privacy & Security**")
                }

                HStack(alignment: .top) {
                    Text("2.")
                        .fontWeight(.bold)
                    Text("Click **Screen Recording** in the sidebar")
                }

                HStack(alignment: .top) {
                    Text("3.")
                        .fontWeight(.bold)
                    Text("Find **Shotter** in the list and toggle it **ON**")
                }

                HStack(alignment: .top) {
                    Text("4.")
                        .fontWeight(.bold)
                    Text("You may need to **restart Shotter** for changes to take effect")
                }
            }

            Spacer()

            HStack {
                Button("Open System Settings") {
                    PermissionManager.shared.openSystemSettings()
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}
```

### Permission Status Monitoring

```swift
import ScreenCaptureKit
import Combine

@MainActor
class PermissionObserver: ObservableObject {
    @Published var isAuthorized = false

    private var pollTimer: Timer?

    init() {
        startPolling()
    }

    func startPolling() {
        // Check permission every 2 seconds
        // This catches when user grants permission in System Settings
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkPermission()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func checkPermission() async {
        if #available(macOS 12.3, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                isAuthorized = !content.displays.isEmpty
            } catch {
                isAuthorized = false
            }
        } else {
            isAuthorized = CGPreflightScreenCaptureAccess()
        }
    }
}
```

---

## Hardened Runtime

Hardened Runtime is required for notarization and provides security protections.

### Xcode Configuration

1. Select project → Target → **Signing & Capabilities**
2. Click **+ Capability**
3. Add **Hardened Runtime**

### Required Runtime Exceptions

For Shotter, no special exceptions are needed. The entitlements file should have:

```xml
<!-- No runtime exceptions required for Shotter -->
```

### Common Hardened Runtime Entitlements

| Entitlement | Purpose | Shotter Needs? |
|-------------|---------|----------------|
| `com.apple.security.cs.allow-jit` | JIT compilation | No |
| `com.apple.security.cs.allow-unsigned-executable-memory` | Unsigned memory | No |
| `com.apple.security.cs.disable-library-validation` | Load unsigned plugins | No |
| `com.apple.security.cs.allow-dyld-environment-variables` | DYLD env vars | No |
| `com.apple.security.device.audio-input` | Microphone | No |
| `com.apple.security.device.camera` | Camera | No |

---

## Distribution Checklist

### Before Distribution

```
[ ] App runs correctly on Apple Silicon
[ ] App runs correctly on Intel Mac
[ ] Screen Recording permission flow works
[ ] Permission denial is handled gracefully
[ ] All features work after permission granted
[ ] App starts from menu bar correctly
[ ] Hotkeys work system-wide
[ ] Preferences window opens/closes
[ ] Quit functionality works
```

### Code Signing Checklist

```
[ ] Xcode signing identity configured
[ ] Team ID is correct
[ ] Entitlements file is linked
[ ] Info.plist is complete
[ ] Build succeeds without signing errors
```

### Notarization Checklist

```
[ ] App-specific password created and stored
[ ] Archive builds successfully
[ ] Notarization submitted without errors
[ ] Notarization approved (check email or status)
[ ] Ticket stapled to app
[ ] spctl verification passes
```

### Distribution Package

```
[ ] Create DMG with background image
[ ] Include drag-to-Applications shortcut
[ ] Test installation on clean macOS
[ ] Test first-launch permission flow
[ ] Verify Gatekeeper doesn't block
```

---

## Troubleshooting

### "Shotter would like to record this computer's screen"

This is the expected system permission dialog. It appears on first capture attempt.

**If dialog doesn't appear**:
1. Reset privacy database: `tccutil reset ScreenCapture`
2. Rebuild the app with a new bundle ID
3. Delete app from Applications and reinstall

### Permission Granted but Capture Fails

1. Ensure the app was restarted after granting permission
2. Check that the correct app is in the Screen Recording list (not an old version)
3. Try removing and re-adding the app in System Settings

### Notarization Fails

Common errors:

| Error | Solution |
|-------|----------|
| "The signature does not include a secure timestamp" | Add `--timestamp` to codesign |
| "The executable does not have the hardened runtime enabled" | Enable Hardened Runtime in Xcode |
| "The signature of the binary is invalid" | Clean build, re-sign |

### App Blocked by Gatekeeper

```bash
# Check why it's blocked
spctl -a -vvv -t install Shotter.app

# If notarization is missing
xcrun stapler staple Shotter.app
```

### Permission Not Persisting After Restart

This usually means the bundle ID or code signature changed between runs. Ensure:
1. Consistent bundle ID
2. Same signing identity
3. Don't change entitlements between builds
