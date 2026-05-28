#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Storyteller"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "→ Building release binary (with embedded Info.plist)…"
cd "$SCRIPT_DIR"

# Embed Info.plist into the binary's __TEXT,__info_plist section —
# this is exactly what Xcode does and what Launch Services expects.
swift build -c release \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "$SCRIPT_DIR/Info.plist" 2>&1

BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

echo "→ Creating .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY"                        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist"         "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon if present
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns"   "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "→ Icon copied."
fi

echo "→ Removing quarantine flags…"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "→ Code-signing ad-hoc…"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "→ Installing to /Applications…"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo "→ Registering with Launch Services…"
# Unregister stale/disabled entry
$LSREG -u "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# Force-register as trusted (the -trusted flag clears launch-disabled)
$LSREG -R -f -trusted "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "✓ Done! Storyteller.app is in /Applications"
echo ""
echo "  ⚠️  One manual step required (Gatekeeper):"
echo "  Open Finder → go to /Applications (⇧⌘A)"
echo "  Right-click Storyteller.app → choose 'Open'"
echo "  Click 'Open' in the security dialog"
echo "  This only needs to be done once."
echo ""
echo "  After that, quit and relaunch Scrivener."
