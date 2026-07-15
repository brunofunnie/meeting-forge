#!/bin/bash
set -euo pipefail

# Builds MeetingForge.app (Release) and packages it into a compressed DMG.
#
# Usage: scripts/package.sh [version]
#   version            label embedded in the DMG filename (default: git describe / "dev")
#
# Environment:
#   CODESIGN_IDENTITY  signing identity, e.g. "Developer ID Application: ..."
#                      (default "-" = ad-hoc signing, fine for local use;
#                      distribution to other Macs needs a real identity + notarization)
#
# Output: dist/MeetingForge.app and dist/MeetingForge-<version>.dmg

cd "$(dirname "$0")/.."

APP_NAME=MeetingForge
VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
DERIVED=build/DerivedData
DIST=dist
BUILD_LOG=build/xcodebuild.log

command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

mkdir -p build

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building Release (log: $BUILD_LOG)"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" build >"$BUILD_LOG" 2>&1; then
  tail -30 "$BUILD_LOG" >&2
  echo "error: build failed — full log at $BUILD_LOG" >&2
  exit 1
fi

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "error: $APP_PATH not found after build" >&2; exit 1; }

echo "==> Staging $DIST/$APP_NAME.app"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_PATH" "$DIST/"

echo "==> Code signing (identity: $IDENTITY)"
codesign --force --deep --options runtime -s "$IDENTITY" "$DIST/$APP_NAME.app"
codesign --verify --deep "$DIST/$APP_NAME.app"

DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
echo "==> Creating $DMG_PATH"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$DIST/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# One-click installer: copies the app to /Applications and strips the
# Gatekeeper quarantine flag (the app is ad-hoc signed, not notarized).
cat > "$STAGING/Install.command" <<'INSTALLER'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/MeetingForge.app"
[ -d "$APP" ] || { echo "MeetingForge.app not found next to this script."; exit 1; }
echo "Installing MeetingForge to /Applications…"
rm -rf /Applications/MeetingForge.app
cp -R "$APP" /Applications/
xattr -dr com.apple.quarantine /Applications/MeetingForge.app 2>/dev/null || true
echo "Installed. Launching…"
open /Applications/MeetingForge.app
INSTALLER
chmod +x "$STAGING/Install.command"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "==> Done"
ls -lh "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME" "$DMG_PATH"
