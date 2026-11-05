#!/bin/zsh
# Builds a Developer ID–signed, notarized and stapled ImmichGallery.dmg (+ .zip) in build/release,
# and the Sparkle appcast.xml that offers the .zip as an in-app update. Publish with scripts/publish.sh.
#
# Requirements:
#   - A "Developer ID Application" certificate in your keychain
#   - Notarization credentials, either:
#       NOTARY_PROFILE=<name>   (created with `xcrun notarytool store-credentials`)
#     or an App Store Connect API key:
#       NOTARY_KEY=/path/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer-uuid>
#
#   - The Sparkle EdDSA private key in your login keychain (see docs/Updates.md)
#
# Optional:
#   TEAM_ID        defaults to the team of the first Developer ID certificate found.
#   RELEASE_NOTES  a Markdown file, shown in the in-app update window and used for the GitHub release.
set -euo pipefail
cd "${0:A:h}/.."

# Machine-local signing configuration, intentionally excluded from version control.
if [[ -f .release.env ]]; then
  source .release.env
fi

APP=ImmichGallery
OUT=build/release
ARCHIVE=build/$APP.xcarchive
PACKAGES=build/SourcePackages
SPARKLE_BIN=$PACKAGES/artifacts/sparkle/Sparkle/bin
REPO_URL=https://github.com/IGOLz/ImmichGallery
[[ -z "${RELEASE_NOTES:-}" || -f "$RELEASE_NOTES" ]] || { echo "RELEASE_NOTES file not found: $RELEASE_NOTES" >&2; exit 1; }

IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
[[ -n "$IDENTITY_LINE" ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }
IDENTITY=$(echo "$IDENTITY_LINE" | sed -E 's/.*"(.*)".*/\1/')
TEAM_ID=${TEAM_ID:-$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')}

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
  NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
  echo "Set NOTARY_PROFILE, or NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER." >&2; exit 1
fi

notarize() {
  echo "→ Notarizing $1"
  xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --timeout 30m | tee "$OUT/notary.log"
  grep -q "status: Accepted" "$OUT/notary.log" || { echo "Notarization failed." >&2; exit 1; }
}

rm -rf "$OUT" "$ARCHIVE"
mkdir -p "$OUT"

echo "→ Archiving with \"$IDENTITY\""
xcodebuild archive -quiet \
  -project $APP.xcodeproj -scheme $APP -configuration Release \
  -archivePath "$ARCHIVE" -destination "generic/platform=macOS" -clonedSourcePackagesDirPath "$PACKAGES" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

cp -R "$ARCHIVE/Products/Applications/$APP.app" "$OUT/"
VERSION=$(defaults read "$PWD/$OUT/$APP.app/Contents/Info.plist" CFBundleShortVersionString)
FEED_URL=$(defaults read "$PWD/$OUT/$APP.app/Contents/Info.plist" SUFeedURL)

# Sparkle ships its helpers ad-hoc signed, and Xcode's "Code Sign on Copy" re-signs only the
# framework itself. Sign them with the Developer ID (no --deep: the Downloader has its own
# entitlements), then re-seal the app, whose signature covers the framework.
echo "→ Signing Sparkle helpers"
SPARKLE="$OUT/$APP.app/Contents/Frameworks/Sparkle.framework"
resign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
resign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
resign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
resign "$SPARKLE/Versions/B/Autoupdate"
resign "$SPARKLE/Versions/B/Updater.app"
resign "$SPARKLE"
resign --preserve-metadata=entitlements,requirements,flags "$OUT/$APP.app"
codesign --verify --deep --strict "$OUT/$APP.app"

# 1. Notarize and staple the app itself, so it also opens offline once copied to /Applications.
ditto -c -k --keepParent "$OUT/$APP.app" "$OUT/$APP-notarize.zip"
notarize "$OUT/$APP-notarize.zip"
xcrun stapler staple "$OUT/$APP.app"
rm "$OUT/$APP-notarize.zip"

# 2. Zip of the stapled app.
ditto -c -k --keepParent "$OUT/$APP.app" "$OUT/$APP-$VERSION.zip"

# 3. Drag-to-Applications disk image, signed, notarized and stapled.
scripts/create-dmg.sh "$OUT/$APP.app" "$VERSION" "$OUT/$APP-$VERSION.dmg"
codesign --sign "$IDENTITY" --timestamp "$OUT/$APP-$VERSION.dmg"
notarize "$OUT/$APP-$VERSION.dmg"
xcrun stapler staple "$OUT/$APP-$VERSION.dmg"

# 4. Sparkle appcast: the published feed plus this version's .zip, signed with the EdDSA key.
#    Older entries are kept, so Macs that can't run this version still find the last one they can.
echo "→ Generating the update feed"
UPDATES=$(mktemp -d)
STATUS=$(curl -sSL -o "$UPDATES/appcast.xml" -w '%{http_code}' "$FEED_URL")
case $STATUS in
  200) ;;
  404) rm -f "$UPDATES/appcast.xml"; echo "  No published feed yet: starting a new one." ;;
  *) echo "Could not download the published feed ($STATUS): $FEED_URL" >&2; exit 1 ;;
esac
cp "$OUT/$APP-$VERSION.zip" "$UPDATES/"
if [[ -n "${RELEASE_NOTES:-}" ]]; then
  cp "$RELEASE_NOTES" "$UPDATES/$APP-$VERSION.md"
  cp "$RELEASE_NOTES" "$OUT/release-notes.md"
fi
"$SPARKLE_BIN/generate_appcast" --embed-release-notes --maximum-versions 0 \
  --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
  --full-release-notes-url "$REPO_URL/releases" --link "$REPO_URL" \
  "$UPDATES"
cp "$UPDATES/appcast.xml" "$OUT/appcast.xml"
rm -rf "$UPDATES"
grep -q "v$VERSION/$APP-$VERSION.zip" "$OUT/appcast.xml" || { echo "appcast.xml has no entry for $VERSION." >&2; exit 1; }

echo "→ Gatekeeper checks"
spctl -a -vv -t exec "$OUT/$APP.app"
spctl -a -vv -t open --context context:primary-signature "$OUT/$APP-$VERSION.dmg"

(cd "$OUT" && shasum -a 256 "$APP-$VERSION.dmg" "$APP-$VERSION.zip" | tee SHA256SUMS.txt)
echo "✓ $OUT/$APP-$VERSION.dmg"
echo "  Publish with: scripts/publish.sh"
