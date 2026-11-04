#!/bin/zsh
# Builds a Developer ID–signed, notarized and stapled ImmichGallery.dmg (+ .zip) in build/release.
#
# Requirements:
#   - A "Developer ID Application" certificate in your keychain
#   - Notarization credentials, either:
#       NOTARY_PROFILE=<name>   (created with `xcrun notarytool store-credentials`)
#     or an App Store Connect API key:
#       NOTARY_KEY=/path/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer-uuid>
#
# Optional: TEAM_ID (defaults to the team of the first Developer ID certificate found).
set -euo pipefail
cd "${0:A:h}/.."

APP=ImmichGallery
OUT=build/release
ARCHIVE=build/$APP.xcarchive

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
  -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

cp -R "$ARCHIVE/Products/Applications/$APP.app" "$OUT/"
VERSION=$(defaults read "$PWD/$OUT/$APP.app/Contents/Info.plist" CFBundleShortVersionString)
codesign --verify --deep --strict "$OUT/$APP.app"

# 1. Notarize and staple the app itself, so it also opens offline once copied to /Applications.
ditto -c -k --keepParent "$OUT/$APP.app" "$OUT/$APP-notarize.zip"
notarize "$OUT/$APP-notarize.zip"
xcrun stapler staple "$OUT/$APP.app"
rm "$OUT/$APP-notarize.zip"

# 2. Zip of the stapled app.
ditto -c -k --keepParent "$OUT/$APP.app" "$OUT/$APP-$VERSION.zip"

# 3. Drag-to-Applications disk image, signed, notarized and stapled.
STAGING=$(mktemp -d)
cp -R "$OUT/$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Immich Gallery $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$OUT/$APP-$VERSION.dmg"
rm -rf "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$OUT/$APP-$VERSION.dmg"
notarize "$OUT/$APP-$VERSION.dmg"
xcrun stapler staple "$OUT/$APP-$VERSION.dmg"

echo "→ Gatekeeper checks"
spctl -a -vv -t exec "$OUT/$APP.app"
spctl -a -vv -t open --context context:primary-signature "$OUT/$APP-$VERSION.dmg"

(cd "$OUT" && shasum -a 256 "$APP-$VERSION.dmg" "$APP-$VERSION.zip" | tee SHA256SUMS.txt)
echo "✓ $OUT/$APP-$VERSION.dmg"
