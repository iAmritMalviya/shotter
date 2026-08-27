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
- **Region capture crops; it deliberately does not use `SCStreamConfiguration.sourceRect`.** ScreenCaptureKit fits `sourceRect` into the destination buffer using its own aspect-preserving, non-upscaling policy and leaves the remainder transparent — which produced correctly-sized images with the content stranded in the top-left corner. Instead the full display is captured at native resolution and the `CGImage` is cropped, which is exact by construction and verified byte-for-byte against an independent full-display crop. Don't reintroduce `sourceRect` as an "optimization".
- **Display geometry comes from `SCContentFilter`, never from a guess.** `filter.contentRect` is the display in **points**; `filter.pointPixelScale` is its pixels-per-point. The old code matched `SCDisplay.displayID` back to an `NSScreen` and fell back to `?? 2.0` when that failed, which silently doubled the buffer on a 1x external monitor. The crop factor is additionally re-derived from the dimensions of the image SCK actually returns.
- **Units:** `SCDisplay.frame`, `SCDisplay.width`/`height`, and `filter.contentRect` are all in points and all agree with `CGDisplayBounds`. Only the output buffer (`config.width`/`height`) and the crop rect are in pixels.
- Captures never touch disk — `ClipboardManager` writes both `NSImage` objects and raw PNG data to `NSPasteboard.general` for max app compatibility.

### Region selection overlay
- `ScreenGeometry.swift` owns the AppKit↔CoreGraphics conversion for the whole app. AppKit global coords are bottom-left origin with Y up; CoreGraphics (and therefore ScreenCaptureKit) is top-left with Y down. Anything crossing that boundary — the selection rect and the mouse location used to pick the full-screen display — flips through there, not by hand.
- `RegionSelectionWindow` is a borderless `.screenSaver`-level `NSWindow` spanning the union of all screens; Escape cancels via a local `NSEvent` monitor (keyCode 53) that is torn down in both the complete and cancel paths.
- `RegionSelectionView.convertToScreenCoordinates` converts view → window → AppKit screen coords, then flips into CG (top-left origin) space via `NSScreen.convertToCGGlobal`. AppKit and CG global space are both anchored on the **primary** display, so the flip must use the primary's height — `ScreenGeometry.swift` resolves it as the screen at AppKit origin `(0,0)`. It must not index `NSScreen.screens[0]` (not guaranteed to be primary, and traps on an empty array) nor use `NSScreen.main` (that is the key-window screen, usually not the primary).
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

### Permission persistence (signing identity)
macOS TCC keys Screen Recording grants on the app's **designated requirement**. With no Apple
Developer team, builds default to ad-hoc signing, whose designated requirement is the binary's
code-directory hash — which changes on every build. That silently revoked the grant on each
rebuild and made capture fail with `SCStreamErrorDomain -3801` ("The user declined TCCs..."),
while System Settings still showed the toggle as on.

**Release** builds are therefore signed with a **local self-signed certificate**, created by
`./setup-signing.sh` and selected via `CODE_SIGN_IDENTITY` in `project.yml`. The designated
requirement becomes `identifier "com.amrit.Shotter" and certificate leaf = H"..."` — tied to the
certificate, not the code — so the grant survives rebuilds. Verify with `codesign -d -r-`; if
that requirement ever mentions a cdhash, signing has silently fallen back to ad-hoc.

**Debug** builds stay ad-hoc on purpose (`CODE_SIGN_IDENTITY: "-"`), so a fresh clone compiles
before anyone has run `setup-signing.sh`. Debug builds are not the ones tested against
`/Applications`, so they do not need a stable identity.

Notes on the setup, all of which cost time to discover:
- The key lives in a **dedicated keychain** (`~/Library/Keychains/shotter-signing.keychain-db`),
  not the login keychain. `codesign` can only use a key whose keychain *partition list* permits
  it, and updating that on the login keychain requires the login **keychain** password — which
  is not necessarily the account password. Symptom if this is wrong: `errSecInternalComponent`
  at the CodeSign build step.
- That keychain's password is generated randomly and stored at
  `~/.config/shotter/signing-keychain-password` (mode 600). Never hardcode it — TCC grants screen
  capture to anything signed by this certificate, so the key is a privileged credential. For the
  same reason the key is imported with `-T /usr/bin/codesign` rather than `-A`, so only codesign
  can use it instead of every process on the machine.
- macOS does **not** unlock this keychain at login the way it does the login keychain, so
  `install.sh` unlocks it before building. Without that, the first build after a reboot fails
  with `errSecInternalComponent` and looks like signing spontaneously broke.
- `setup-signing.sh` is idempotent and refuses to regenerate unless given `--force`. Forcing it
  issues a **new** certificate, which changes the designated requirement and throws away the
  Screen Recording grant — reintroducing the exact bug it exists to prevent.
- The certificate is **not trusted**, and does not need to be. `security find-identity -v -p
  codesigning` will not list it (`CSSMERR_TP_NOT_TRUSTED`), but `codesign` signs with it fine.
  Setting trust requires an admin authorization dialog; skip it.
- Generate the PKCS#12 with **`/usr/bin/openssl`** (LibreSSL). Homebrew's OpenSSL 3 writes
  algorithms the macOS Security framework rejects: `MAC verification failed during PKCS12 import`.
- If a `codesign` process is ever killed mid-build, delete the leftover `*.cstemp` inside the
  app bundle in DerivedData. It poisons every later signing attempt with `invalid or unsupported
  format for signature`.

Test capture against `/Applications/Shotter.app` via `./install.sh` rather than a build run from
Xcode, so the app has a stable path as well as a stable identity.

### State, concurrency, and singletons
- Service singletons (`ScreenCaptureService.shared`, `ClipboardManager.shared`, `PermissionManager.shared`) — all `@MainActor`-isolated where they touch AppKit.
- User-facing settings live in `UserDefaults` and are read via `@AppStorage` in SwiftUI views (`PreferencesView`) and direct `UserDefaults.standard` reads in services. Defaults for `playSoundOnCapture` and `showNotification` are registered in `AppDelegate.applicationDidFinishLaunching` — when adding a new setting, register its default there. (`launchAtLogin` is deliberately unregistered: absent means off, and it is applied via `SMAppService.mainApp`.)

## Known state of the code

- `SPEC.md` is the live bug-fix spec — read it before touching capture geometry. Bug 1 (permission persistence) is decided but its `install.sh` is unwritten. Bug 2 (region capture producing padded images) is **fixed** by the crop rewrite above; note the spec's proposed fix — scaling `sourceRect` into pixels — was tested and is *not* correct, because SCK's own fit policy still strands content in a corner. Bug 3's Y-flip anchor is fixed; cross-monitor selections remain intentionally clipped to the display under the selection's center. It also lists explicitly out-of-scope items — don't bundle them into an unrelated diff.
- `CGWindowListCreateImage`, used by the window-capture path, is marked **unavailable** (not merely deprecated) in the current macOS SDK. It compiles only because the deployment target is 14.0. Raising `MACOSX_DEPLOYMENT_TARGET` will break that path and force a ScreenCaptureKit rewrite of window capture.
- Unused code that is not a mistake to "discover": `CaptureMode` (its `shortcutHint` still says `⌘⇧3/4/5` and is stale), `ClipboardManager.copyImageData`, `CaptureError.screenAsleep`/`.screenLocked`, and the `StreamOutput` fallback.
- `docs/` holds the pre-implementation design notes (project overview, hotkey/permission research, SwiftUI examples). They predate the code and are **not** authoritative — read the source, not `docs/`, when the two disagree.

## Verifying capture changes

There are no tests, and the coordinate math can't be reasoned into correctness. Any change to capture geometry, scaling, or the selection overlay must be checked by hand on the user's machine (2560×1600 Retina, occasionally dual-monitor): capture a region containing a recognizable UI element, paste into Preview, and confirm the image is exactly `selection × scale` pixels with no padding, no stretching, and no offset.

## Workflow

After completing each prompt/task, commit and push all changes to git. Do not add co-author lines to commits. Commit each logical fix separately rather than bundling.
