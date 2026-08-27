# Shotter — Bug Fix Spec

**Scope:** Three reported bugs. No new features, no refactors beyond what each fix requires. General code conventions and project structure are documented in `CLAUDE.md` and not repeated here.

**Status:** Approved scope — Bug 1 (Option B) and Bug 2 only. Bug 3 deferred until user reconnects second display.

---

## Bug 1 — Screen Recording permission re-prompts on every rebuild

### Symptom
After granting Screen Recording permission to Shotter, the OS prompts for it again on the next Debug rebuild. User has to re-enable Shotter in **System Settings → Privacy & Security → Screen Recording** repeatedly.

### Reproduction
1. Run a Debug build → grant Screen Recording permission.
2. Make any code change.
3. Run again → permission prompt reappears; Shotter no longer captures.

### Prior attempt
Commit `470a205` set `ENABLE_HARDENED_RUNTIME: NO` for Debug. This addressed *one* of the inputs to TCC's identity check, but **did not solve the root cause**.

### Root cause
macOS TCC stores Screen Recording grants keyed by the binary's **code-directory hash (cdhash) + bundle ID**. With the current `project.yml` setup:

- `CODE_SIGN_STYLE: Automatic`
- `DEVELOPMENT_TEAM: ""` (empty)
- No real signing identity

Xcode falls back to **ad-hoc signing** (`codesign -s -`). Ad-hoc signatures embed the binary's content hash, so the cdhash changes on every rebuild → TCC sees a "different" app → grant is invalidated.

Disabling hardened runtime removes the hardened-runtime flag from the cdhash inputs but the binary content itself still changes per build.

### Acceptance criteria
- After a single grant, Screen Recording permission persists across at least 10 consecutive Debug rebuilds without user re-intervention.
- The fix does not require an Apple Developer account (user has no paid team).
- The fix is documented in `CLAUDE.md` so future agents understand the constraint.

### Fix (chosen: Option B — install Release to /Applications)

Accept ad-hoc Debug builds will always re-prompt. Test capture functionality against Release builds installed to `/Applications/Shotter.app` instead — TCC keys on the stable install path + Release's stable signature.

**Concrete deliverables:**
1. Add an `install.sh` (or `scripts/install-release.sh`) at repo root that:
   - Runs `xcodebuild -project Shotter.xcodeproj -scheme Shotter -configuration Release build`
   - Locates the built `.app` in DerivedData
   - Removes any existing `/Applications/Shotter.app`
   - Copies the new build to `/Applications/Shotter.app`
   - Prints the path and a reminder to grant Screen Recording permission on first run
2. Update `CLAUDE.md` with a new "Permission persistence" section explaining:
   - Debug builds re-prompt every rebuild (macOS ad-hoc signing limitation; not fixable without paid Developer ID)
   - For real testing of capture, run `./install.sh` and use the `/Applications/Shotter.app` build
   - Why this happens (cdhash changes per build, TCC keys on cdhash + bundle ID)
3. Add the script invocation to `README.md` under a "Testing capture functionality" subsection.

### Verification
- Run `./install.sh`, grant Screen Recording permission once, capture full-screen.
- Run `./install.sh` again (rebuild + reinstall), confirm capture still works **without** re-prompting.
- Repeat 3 times. Permission should persist for `/Applications/Shotter.app` across reinstalls because the Release signing identity is stable.

---

## Bug 2 — Region capture (Opt+Shift+4) captures extra whitespace

### Symptom
User selects a region with Opt+Shift+4; the resulting clipboard image is **larger than the selection**, with the actual captured content sitting in one corner and the rest padded with white/blank pixels.

User's display: **2560×1600 Retina** (`backingScaleFactor = 2.0`).

### Reproduction
1. Press Opt+Shift+4.
2. Drag-select a 400×300 region in the middle of the screen.
3. Paste the clipboard image into Preview.
4. Image is, e.g., 800×600 with actual screen content filling only 400×300 of the top-left corner; remainder is blank.

### Root cause (hypothesis to verify)
At `Shotter/Services/ScreenCaptureService.swift:144-152`:

```swift
let scale = backingScaleFactor(for: display)   // 2 on Retina
let filter = SCContentFilter(display: display, excludingWindows: [])
let config = SCStreamConfiguration()

config.sourceRect = clampedRect                  // CGRect in POINTS
config.width  = Int(clampedRect.width)  * scale  // PIXELS
config.height = Int(clampedRect.height) * scale  // PIXELS
```

The unit mismatch:
- `SCStreamConfiguration.sourceRect` is interpreted by ScreenCaptureKit in **pixels** (matching `SCDisplay.width`/`height`, which are pixel values).
- We pass `clampedRect` in **points** (it was derived from `display.frame`, which is in points).
- On a 2x Retina display, a 400×300-point selection becomes a 400×300-**pixel** sourceRect to SCK — i.e., only half the area the user selected (the top-left quadrant in point space).
- The output buffer is correctly sized at `800×600` pixels.
- SCK samples 400×300 pixels of source content into an 800×600 output buffer. Depending on SCK's scaling/padding behavior, this either stretches the half-content to fill, or pads with empty pixels — matching the user's "extra whitespace in one corner" observation.

### Fix
Convert `sourceRect` to pixels before assignment:

```swift
config.sourceRect = CGRect(
    x: clampedRect.origin.x * CGFloat(scale),
    y: clampedRect.origin.y * CGFloat(scale),
    width:  clampedRect.width  * CGFloat(scale),
    height: clampedRect.height * CGFloat(scale)
)
config.width  = Int((clampedRect.width  * CGFloat(scale)).rounded())
config.height = Int((clampedRect.height * CGFloat(scale)).rounded())
```

Also: `backingScaleFactor(for:)` currently returns `Int`, losing precision on non-integer scales. Change return type to `CGFloat` and propagate. (Pure Retina is always 1.0 or 2.0, but external 1x displays exist and the current `?? 2.0` fallback is wrong for them.)

### Acceptance criteria
- 400×300-point selection on a 2x Retina display produces an 800×600-pixel clipboard image where every pixel is real captured content (no whitespace padding).
- Selection on a 1x external display (if user has one) produces a 1:1 pixel image with no padding.
- Selection that exactly fits one corner of the screen still works (no off-by-one cropping).

### Verification
- Manual: select a region containing a recognizable UI element (e.g., a button), paste into Preview, confirm the element fills the image with no whitespace and is not stretched.
- If practical, automated test against `computeScaledSourceRect(_:scale:)` extracted as a pure function (see test-engineer notes from the prior review).

---

## Bug 3 — Region capture does not work correctly on a second monitor

**DEFERRED:** User does not have a second display connected right now. Skip this bug in this round. Re-tackle when display is reconnected and user can verify the fix.

The analysis below is preserved for the future fix.

### Symptom
When the user has two displays connected and performs region capture on the non-primary display, the result is wrong — exact failure mode TBD (likely captures the wrong area, or the wrong display entirely, given the code).

### Reproduction (need user to confirm)
1. Connect a second display.
2. Press Opt+Shift+4.
3. Drag-select a region on the **non-primary** display.
4. Paste — image is wrong (wrong area / wrong display / blank).

### Root cause candidates (multiple; one or more may be active)

**Candidate A — Display selection by region center is fragile**
`ScreenCaptureService.swift:124-126` picks the destination display by the selection's **center point**. A selection straddling two displays loses everything outside the center's display — currently with no error. Acceptable behavior, but worth documenting.

**Candidate B — Y-flip uses `NSScreen.screens[0]` not the actual primary**
`RegionSelectionWindow.swift:208`:
```swift
let primaryScreenHeight = NSScreen.screens[0].frame.height
```
Apple does **not** guarantee `screens[0]` is the menu-bar (primary) screen — only that `NSScreen.screens` contains all displays. The CG↔AppKit Y-flip must be anchored on the actual primary screen (the one at AppKit origin (0,0)). If `screens[0]` is a secondary display with a different height, every coordinate on every monitor is off by the difference.

**Candidate C — Display.frame coordinate space assumptions**
Once Bug 2's pixel/point issue is fixed, the multi-monitor `localRect` math (`ScreenCaptureService.swift:128-134`) also needs to be revisited — `display.frame.origin` is in points (CG global), and the subtraction must happen entirely in one unit system before multiplying by scale.

**Candidate D — `NSScreen.screens[0]` crash on empty array**
`RegionSelectionWindow.swift:208` crashes if `NSScreen.screens` is empty (rare, but possible during display sleep/wake). Defensive only; not the primary bug.

### Fix
1. Replace `NSScreen.screens[0].frame.height` with the height of the actual primary screen, identified by AppKit origin (0,0):
   ```swift
   let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
       ?? NSScreen.main?.frame.height
       ?? 0
   ```
2. Confirm `display.frame` returned by `SCShareableContent` matches CG global coordinates (top-left origin). If it doesn't on the user's setup, adjust the `localRect` math accordingly.
3. Extract the coordinate conversion into a pure helper so it can be tested with mock screen geometry.

### Acceptance criteria
- Region capture on a non-primary display produces an image of the exact selected area, correctly positioned.
- Region capture on the primary display still works (no regression).
- Selecting across displays clips to the display under the selection's center (current behavior, but verified) and does not silently capture the wrong display.

### Verification
- Manual: select a region on the secondary display containing a recognizable UI element, confirm correct content.
- Manual: select a region that straddles both displays, confirm output matches the portion on the chosen display.
- If user does not currently have a second display hooked up, request a screenshot/video of the bug or defer this fix until they reconnect.

---

## Out of scope (explicitly NOT fixing in this round)

These were flagged in the prior code review but are not part of this spec:

- `kCGWindowSharingNone` privacy gap (security audit Critical #1)
- Clipboard image persistence / concealed pasteboard marker (security audit Critical #2)
- Dead `StreamOutput` fallback code (architecture finding)
- Hotkey configuration validation
- Notification authorization timing
- `DEVELOPMENT_TEAM: ""` in Release config (related to Bug 1 but not the same fix)
- Adding a test target

Each of these deserves its own follow-up. Don't bundle them into the bug-fix PR — keep the diff surgical so it's easy to verify and easy to revert if anything regresses.

---

## Boundaries

**Always:**
- Run `xcodegen generate` after touching `project.yml`.
- Test capture on the user's actual machine (2560×1600 Retina, sometimes dual-monitor) before declaring done. The capture math cannot be unit-tested into correctness — it has to be eyeballed.
- Commit after each bug fix individually; do not bundle.
- Update `CLAUDE.md` if Bug 1's fix changes the signing setup.

**Ask first:**
- Before changing `backingScaleFactor`'s return type from `Int` to `CGFloat` (touches multiple call sites — small ripple).
- Before adding any test infrastructure as part of the fix (test-engineer recommended deferring; honor that unless you change your mind).

**Never:**
- Don't "modernize" Carbon hotkey code as a side effect — it's load-bearing (see `CLAUDE.md`).
- Don't change the empty entitlements file. Sandbox stays off intentionally.
- Don't add the privacy/security fixes in the same PR as these bug fixes. Separate concerns.

---

## Verification story

Before considering this spec complete:

1. ☑ User picked Bug 1 Option B (install Release to /Applications).
2. ☑ Bug 3 deferred — user lacks second display right now.
3. ☐ Bug 2 fix verified: clipboard image is the exact pixel dimensions of the selection × scale, with no whitespace.
4. ☐ Bug 1 fix verified: `./install.sh` → grant once → 3 reinstalls without re-prompt.
5. ☐ `CLAUDE.md` updated with the "Permission persistence" section explaining the Debug limitation.
6. ☐ `README.md` updated with the install script invocation.
7. ☐ Bug 1 and Bug 2 committed as separate commits.
