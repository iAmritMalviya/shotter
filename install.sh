#!/usr/bin/env bash
#
# Build Shotter in Release and install it to /Applications.
#
# Why this exists: with no Apple Developer team configured, builds are ad-hoc signed, so the
# binary's code-directory hash changes whenever the code does. macOS TCC keys Screen Recording
# grants on that hash plus the bundle ID, which is why a Debug build loses the permission on
# every rebuild. Testing capture against a stable copy at /Applications/Shotter.app means you
# grant once and can then launch, quit and relaunch it freely without re-granting.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

APP_NAME="Shotter"
DEST="/Applications/${APP_NAME}.app"

echo "==> Building ${APP_NAME} (Release)"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release build \
    | grep -E "^\*\*|error:|warning: .*deprecated" || true

echo "==> Locating built product"
BUILT_DIR="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"
SRC="${BUILT_DIR}/${APP_NAME}.app"

if [[ ! -d "$SRC" ]]; then
    echo "error: built app not found at ${SRC}" >&2
    exit 1
fi
echo "    ${SRC}"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting running ${APP_NAME}"
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "==> Installing to ${DEST}"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "==> Signature"
codesign -dvv "$DEST" 2>&1 | grep -E 'Identifier|Signature|CDHash' | sed 's/^/    /' || true

cat <<NOTE

Installed. Launch it with:

    open "${DEST}"

Shotter lives in the menu bar and has no Dock icon. On first run, grant
System Settings -> Privacy & Security -> Screen Recording, then relaunch it.

Shortcuts: Option+Shift+3 full screen, Option+Shift+4 region, Option+Shift+5 window.

Caveat: this build is ad-hoc signed (DEVELOPMENT_TEAM is empty in project.yml), so its
code-directory hash changes whenever the source changes. Reinstalling after a code change
can still require re-granting Screen Recording once. Launching, quitting and relaunching
an already-installed build keeps the grant.
NOTE
