# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

`CLAUDE.md` is a near-verbatim copy of this file for Claude Code. When you change one, mirror the change into the other.

## Build Commands

The Xcode project is generated from `project.yml` via XcodeGen — `project.yml` is the source of truth. Modifying targets, build settings, entitlements, or deployment target means editing `project.yml` and re-running `xcodegen generate`. Do not edit `Shotter.xcodeproj/project.pbxproj` directly.

```bash
xcodegen generate                                                          # regenerate Xcode project after project.yml changes
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Debug build
xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release build
```

There is no test target, lint config, or CI pipeline in this repo. Capture correctness is verified by eye — see "Verifying capture changes" below.

## Architecture

macOS 14+ menu-bar utility (`LSUIElement = YES`, no Dock icon). SwiftUI + AppKit hybrid: `ShotterApp` is a minimal `App` that only hosts the `Settings` scene; everything else — status item, hotkeys, capture, lifecycle — runs out of `AppDelegate` via `@NSApplicationDelegateAdaptor`. Treat `AppDelegate.applicationDidFinishLaunching` as the real entry point.

Every capture path converges on `MenuBarController`: hotkeys (`AppDelegate.registerHotkeys`) and menu items both call its `@objc` capture methods, which run `ScreenCaptureService` → `ClipboardManager.copy` → `showSuccessFeedback()` / `showErrorAlert(_:)`. Add a new capture entry point there, not in a new controller.

### Capture pipeline
- `ScreenCaptureService` (singleton, `@MainActor`) uses **ScreenCaptureKit** for full-screen and region captures, and **legacy `CGWindowListCreateImage`** for window captures (kept because per-window ScreenCaptureKit filtering is heavier and CGWindowList is still functional for single-window snapshots).
- `captureWithFilter` calls `SCScreenshotManager.captureImage` for single-frame capture. The `StreamOutput` + `withCheckedThrowingContinuation` fallback that follows the `if #available(macOS 14.0, *)` block is **unreachable dead code** — the deployment target is already 14.0, so the guard never fails. It's knowingly left in place; removing it is a separate cleanup, not something to fold into an unrelated change.
- Multi-monitor handling: full-screen picks the display under the **mouse cursor** (sampled *before* the first `await`, deliberately, so cursor movement during the async hop can't change the target); region picks the display under the **region's center**, then clamps the rect to display bounds. Cross-monitor selections are intentionally clipped, not stitched. `mouseLocationCG` and `displayContaining` are the helpers; backing scale factor is resolved by matching `SCDisplay.displayID` to `NSScreen.deviceDescription["NSScreenNumber"]`.
- **Units are the recurring hazard here.** `SCDisplay.frame` and the rect coming out of `RegionSelectionWindow` are in **points**; `SCDisplay.width`/`height` and `SCStreamConfiguration.sourceRect` are in **pixels**. Do all rect arithmetic in one unit system before multiplying by scale. (`config.sourceRect` is currently assigned a point-space rect — that's the open Bug 2 in `SPEC.md`.)
- Captures never touch disk — `ClipboardManager` writes both `NSImage` objects and raw PNG data to `NSPasteboard.general` for max app compatibility.

### Region selection overlay
- `RegionSelectionWindow` is a borderless `.screenSaver`-level `NSWindow` spanning the union of all screens; Escape cancels via a local `NSEvent` monitor (keyCode 53) that is torn down in both the complete and cancel paths.
- `RegionSelectionView.convertToScreenCoordinates` converts view → window → AppKit screen coords, then flips Y into CG (top-left origin) space. The flip is currently anchored on `NSScreen.screens[0]`, which macOS does **not** guarantee is the primary/menu-bar screen — this is the known multi-monitor bug (Bug 3 in `SPEC.md`, deferred).
- Drags under 10×10 points are treated as a cancel, not a capture.

### Global hotkeys (Carbon)
- `HotkeyManager` uses **Carbon `RegisterEventHotKey`** because it's still the only way to register truly global hotkeys without Accessibility permission. Do not "modernize" this to NSEvent monitors — those require Accessibility access.
- The Carbon C event handler callback cannot capture Swift context, so it dispatches via a file-scope `hotkeyManagerInstance` global. This singleton pattern is load-bearing — don't try to pass `self` into the callback.
- Hotkey IDs are typed via `HotkeyAction` raw values; the event signature `'SHTR'` (`0x5348_5452`) namespaces our hotkeys.
- Defaults are `Option+Shift+3/4/5` — deliberately offset from macOS `Cmd+Shift+3/4/5` so both coexist. Custom bindings persist via `UserDefaults` (JSON-encoded `HotkeyConfiguration`); `updateHotkey(for:config:)` unregisters, saves, and re-registers while preserving the existing callback.

### Post-capture feedback
- `MenuBarController.showSuccessFeedback()` plays the system screenshot sound by loading `/System/Library/Components/CoreAudio.component/.../SystemSounds/system/Screen Capture.aif` into a `SystemSoundID` at init, and posts a `UNUserNotification`. Both are gated on `UserDefaults` toggles (`playSoundOnCapture`, `showNotification`).
- Notification authorization is requested in `applicationDidFinishLaunching` without awaiting the result — a first capture can fire before the grant lands.

### Permissions & signing
- Screen Recording permission is checked/triggered by calling `SCShareableContent.excludingDesktopWindows(...)` — there's no dedicated request API. `PermissionManager` exposes the resulting state via `@Published isAuthorized`, which `MenuBarController` observes to enable/disable capture menu items.
- The app's `Shotter.entitlements` is intentionally empty (`<dict/>`) — **sandboxing is off**, required for screen capture. Don't add the sandbox entitlement.
- `project.yml` sets `ENABLE_HARDENED_RUNTIME: NO` for Debug, `YES` for Release (commit `470a205`). Don't enable hardened runtime in Debug.

### Permission persistence (why Debug builds keep re-prompting)
macOS TCC keys Screen Recording grants on the binary's **cdhash + bundle ID**. `project.yml` has `CODE_SIGN_STYLE: Automatic` with an empty `DEVELOPMENT_TEAM`, so builds are **ad-hoc signed** — the cdhash changes on every rebuild, TCC sees a different app, and the grant is invalidated. The Debug hardened-runtime exception above removes one input to that hash but does **not** fix the root cause; without a paid Developer ID this is not fixable.

Accepted workaround: **test capture against a Release build installed at `/Applications/Shotter.app`**, where the stable install path plus Release signing keeps the grant. Build Release, then replace `/Applications/Shotter.app` with the product from DerivedData and grant permission once. (`SPEC.md` specifies an `install.sh` to automate this; it has not been written yet.)

### State, concurrency, and singletons
- Service singletons (`ScreenCaptureService.shared`, `ClipboardManager.shared`, `PermissionManager.shared`) — all `@MainActor`-isolated where they touch AppKit.
- User-facing settings live in `UserDefaults` and are read via `@AppStorage` in SwiftUI views (`PreferencesView`) and direct `UserDefaults.standard` reads in services. Defaults for `playSoundOnCapture` and `showNotification` are registered in `AppDelegate.applicationDidFinishLaunching` — when adding a new setting, register its default there. (`launchAtLogin` is deliberately unregistered: absent means off, and it is applied via `SMAppService.mainApp`.)

## Known state of the code

- `SPEC.md` is the live bug-fix spec — read it before touching capture geometry. Bug 1 (permission persistence) is decided but its `install.sh` is unwritten; Bug 2 (region capture point/pixel mismatch producing padded images) is **open**; Bug 3 (second-monitor region capture) is deferred until the user reconnects a second display. It also lists explicitly out-of-scope items — don't bundle them into an unrelated diff.
- Unused code that is not a mistake to "discover": `CaptureMode` (its `shortcutHint` still says `⌘⇧3/4/5` and is stale), `ClipboardManager.copyImageData`, `CaptureError.screenAsleep`/`.screenLocked`, and the `StreamOutput` fallback.
- `docs/` holds the pre-implementation design notes (project overview, hotkey/permission research, SwiftUI examples). They predate the code and are **not** authoritative — read the source, not `docs/`, when the two disagree.

## Verifying capture changes

There are no tests, and the coordinate math can't be reasoned into correctness. Any change to capture geometry, scaling, or the selection overlay must be checked by hand on the user's machine (2560×1600 Retina, occasionally dual-monitor): capture a region containing a recognizable UI element, paste into Preview, and confirm the image is exactly `selection × scale` pixels with no padding, no stretching, and no offset.

## Workflow

After completing each prompt/task, commit and push all changes to git. Do not add co-author lines to commits. Commit each logical fix separately rather than bundling.
