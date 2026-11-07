#!/bin/zsh
# Publishes what scripts/release.sh built in build/release as the latest GitHub release.
#
# The release is created as a draft, gets all its files, and only then is published. Installed
# apps read the update feed from the latest release's appcast.xml, so it never points at a
# release whose .zip isn't uploaded yet.
#
# Usage: scripts/publish.sh [--prerelease]
#   Release notes come from build/release/release-notes.md (RELEASE_NOTES given to release.sh).
#   A pre-release is not "latest", so installed apps are not offered it.
set -euo pipefail
cd "${0:A:h}/.."

APP=ImmichGallery
OUT=build/release
REPO=IGOLz/ImmichGallery
[[ -d "$OUT/$APP.app" ]] || { echo "Run scripts/release.sh first." >&2; exit 1; }
VERSION=$(defaults read "$PWD/$OUT/$APP.app/Contents/Info.plist" CFBundleShortVersionString)
TAG=v$VERSION
FILES=("$OUT/$APP-$VERSION.dmg" "$OUT/$APP-$VERSION.zip" "$OUT/appcast.xml" "$OUT/SHA256SUMS.txt")
for file in "${FILES[@]}"; do [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }; done
grep -q "$TAG/$APP-$VERSION.zip" "$OUT/appcast.xml" || { echo "appcast.xml has no entry for $VERSION." >&2; exit 1; }

NOTES=(--generate-notes)
[[ -f "$OUT/release-notes.md" ]] && NOTES=(--notes-file "$OUT/release-notes.md")
EXTRA=()
[[ "${1:-}" == "--prerelease" ]] && EXTRA=(--prerelease)

echo "→ Creating draft release $TAG"
gh release create "$TAG" -R "$REPO" --draft --title "Immich Gallery $VERSION" "${NOTES[@]}" "${EXTRA[@]}" "${FILES[@]}"
echo "→ Publishing $TAG"
gh release edit "$TAG" -R "$REPO" --draft=false
echo "✓ https://github.com/$REPO/releases/tag/$TAG"

# Prereleases never change the stable Homebrew channel.
if [[ "${1:-}" != "--prerelease" ]]; then
  echo "→ Updating the Homebrew tap"
  python3 scripts/update-homebrew.py "$TAG" || {
    echo "Release is live; retry: python3 scripts/update-homebrew.py $TAG" >&2
    exit 1
  }
fi
