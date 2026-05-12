#!/bin/bash
# Build Boulder.dmg — drag-to-Applications installer with a polished
# Finder layout. Same structure as the NotchPop / WallPop installers.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(find build -type d -name 'Boulder.app' -path '*Build/Products/Release/*' | head -1)"
if [ -z "$APP" ]; then
  echo "Build the app first via ./scripts/build.sh"
  exit 1
fi

VOLNAME="Boulder"
DMG_OUT="$(pwd)/Boulder.dmg"
STAGING="$(mktemp -d -t boulder-dmg)"
WORK_DIR="$(mktemp -d -t boulder-dmg-work)"
trap "rm -rf '$STAGING' '$WORK_DIR'" EXIT

echo "→ Staging at $STAGING"
cp -R "$APP" "$STAGING/Boulder.app"
ln -s /Applications "$STAGING/Applications"

WRITABLE_DMG="$WORK_DIR/boulder-rw.dmg"
STAGE_KB=$(du -sk "$STAGING" | awk '{print $1}')
SIZE_KB=$((STAGE_KB + 16384))
echo "→ Creating writable DMG (staging $STAGE_KB KB, image $SIZE_KB KB)"
hdiutil create -srcfolder "$STAGING" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -format UDRW \
  -size "${SIZE_KB}k" \
  "$WRITABLE_DMG" >/dev/null

echo "→ Mounting + decorating"
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$WRITABLE_DMG")"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | grep -oE '/Volumes/[A-Za-z0-9_.-]+' | head -1)"
if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
  echo "Failed to detect mount point in hdiutil output:"
  printf '%s\n' "$ATTACH_OUTPUT"
  exit 1
fi
echo "  mounted at $MOUNT_DIR"

osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 480}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set position of item "Boulder.app" of container window to {150, 180}
    set position of item "Applications" of container window to {410, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
chmod -Rf go-w "$MOUNT_DIR" || true
hdiutil detach "$MOUNT_DIR" -force >/dev/null

echo "→ Compressing DMG"
rm -f "$DMG_OUT"
hdiutil convert "$WRITABLE_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_OUT" >/dev/null

echo ""
echo "✓ Built:"
ls -lh "$DMG_OUT"
echo ""
echo "Open it: open '$DMG_OUT'"
