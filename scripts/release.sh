#!/bin/bash
# Cut a Boulder release end-to-end:
#   1. Bump MARKETING_VERSION in project.yml (source of truth)
#   2. Build Boulder.app + Boulder.dmg
#   3. Sign DMG with Sparkle EdDSA key
#   4. Prepend a fresh <item> to website/appcast.xml
#   5. Print the gh release + wrangler deploy commands to run next.
#
# Usage:
#   ./scripts/release.sh 1.0.1 "What's new (HTML allowed)"

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES_HTML="${2:-Bug fixes and improvements.}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> [release-notes-html]"
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be MAJOR.MINOR.PATCH"
  exit 1
fi

echo "→ Setting MARKETING_VERSION = $VERSION in project.yml"
sed -i '' 's/^\(    MARKETING_VERSION: "\)[^"]*\("\)/\1'"$VERSION"'\2/' project.yml

CURRENT_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([0-9]+)".*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "→ Bumping CURRENT_PROJECT_VERSION $CURRENT_BUILD → $NEW_BUILD"
sed -i '' 's/^\(    CURRENT_PROJECT_VERSION: "\)[0-9]*\("\)/\1'"$NEW_BUILD"'\2/' project.yml

echo "→ Building Boulder.app"
./scripts/build.sh > /dev/null

echo "→ Packaging Boulder.dmg"
./scripts/build-dmg.sh > /dev/null

DMG="$(pwd)/Boulder.dmg"
DMG_SIZE=$(stat -f%z "$DMG")

if [ ! -x "scripts/sparkle/bin/sign_update" ]; then
  echo "⚠️  scripts/sparkle/bin/sign_update not found."
  echo "    Vendor Sparkle's CLI tools into scripts/sparkle/ — copy"
  echo "    the bin/ folder from any other gravy project (NotchPop)."
  echo "    Skipping signature; appcast will be unsigned (dev only)."
  EDSIG=""
else
  echo "→ Signing DMG with EdDSA"
  SIGN_OUT="$(./scripts/sparkle/bin/sign_update "$DMG")"
  EDSIG="$(printf '%s\n' "$SIGN_OUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
  if [ -z "$EDSIG" ]; then
    echo "Failed to extract edSignature from sign_update output:"
    echo "$SIGN_OUT"
    exit 1
  fi
fi

APPCAST="website/appcast.xml"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

if [ -n "$EDSIG" ]; then
  SIG_ATTR="sparkle:edSignature=\"$EDSIG\""
else
  SIG_ATTR=""
fi

NEW_ITEM=$(cat <<EOF
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        $NOTES_HTML
      ]]></description>
      <enclosure
        url="https://github.com/bendawg2010/Boulder/releases/download/v$VERSION/Boulder.dmg"
        sparkle:version="$VERSION"
        sparkle:shortVersionString="$VERSION"
        length="$DMG_SIZE"
        type="application/octet-stream"
        $SIG_ATTR />
    </item>

EOF
)

TMP_ITEM=$(mktemp)
TMP_OUT=$(mktemp)
printf '%s\n' "$NEW_ITEM" > "$TMP_ITEM"

INSERTED=0
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$TMP_OUT"
  if [ $INSERTED -eq 0 ] && echo "$line" | grep -q '</description>'; then
    cat "$TMP_ITEM" >> "$TMP_OUT"
    INSERTED=1
  fi
done < "$APPCAST"

if [ $INSERTED -ne 1 ]; then
  echo "Failed to find <description> in $APPCAST"
  rm -f "$TMP_ITEM" "$TMP_OUT"
  exit 1
fi
mv "$TMP_OUT" "$APPCAST"
rm -f "$TMP_ITEM"

echo ""
echo "✓ Release prepped:"
echo "  Version:    $VERSION"
echo "  DMG:        $DMG ($DMG_SIZE bytes)"
echo "  Appcast:    $APPCAST"
echo "  edSig:      ${EDSIG:-<unsigned>}"
echo ""
echo "Next steps:"
echo "  1) git diff website/appcast.xml"
echo "  2) gh release create v$VERSION '$DMG' --title 'v$VERSION' --notes '$NOTES_HTML'"
echo "  3) (cd website && npx wrangler pages deploy . --project-name=boulder --branch=main --commit-dirty=true)"
echo "  4) git add -A && git commit -m 'v$VERSION' && git push"
