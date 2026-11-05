# Desktop widget

"Featured Photos" is an Apple Photos–style WidgetKit widget (small, medium, large and extra large) that shows one photo at a time and changes it every hour.

## How it works

- **The app prepares the photos.** `WidgetFeedUpdater` (app target) downloads up to 24 previews: today's memories first (at most 4 per memory, half the pool; only if memories are enabled in the user's preferences), then `POST /search/random` images from the timeline. Each preview is downscaled to a 1280 px JPEG and written with `manifest.json` to `<App Group container>/Widget`.
- **The widget only reads them.** The extension has the sandbox and the App Group, and nothing else: no network, no Keychain, never a credential. `manifest.json` stores a SHA-256 of the account, not the account itself.
- **Refresh.** On sign-in and account switch, when the app becomes active, and every hour while it runs, the pool is rebuilt if it is from another day, older than 6 hours, or from another account. It is skipped when no widget is installed. Switching accounts removes the previous account's photos at once, and signing out deletes them all. If the app doesn't run, the widget keeps cycling through the last pool.
- **Clicks.** A memory photo opens `immichgallery://memory/<id>` (the memory player). Other photos open `immichgallery://photo/<id>` (a simple photo window, `WidgetPhotoScene`). The empty widget opens `immichgallery://open`, which shows a library window and starts the first refresh. `MacIntegrationLifecycle` handles the URL Apple event directly, so SwiftUI doesn't open an extra library window for each click, and the account is restored at launch even without a library window. Only UUIDs are accepted, because any web page can open the scheme.

## App Group and signing

The group is `$(TeamIdentifierPrefix)dev.igol.ImmichGallery`. It is the `IMMICH_APP_GROUP` build setting, which is used in both entitlements files and in the `ImmichAppGroup` key of both Info.plist files.

- **Release builds** (`scripts/release.sh`, which sets `DEVELOPMENT_TEAM`) get `884UZN5CH3.dev.igol.ImmichGallery`. A team-prefixed group works with Developer ID on macOS 15 and later without a provisioning profile.
- **Local ad-hoc Debug builds** have no team, so the group has no prefix. macOS may then ask for permission to access data from other apps, or block the container. In that case the widget stays empty. Sign Debug builds with the team to try the widget.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the project-level build settings, so the app and the extension always match.

## Verification

- `xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build`. The `.appex` is embedded in `Contents/PlugIns`.
- `python3 scripts/check-mac-localization.py` also covers `ImmichGalleryWidget/Localizable.xcstrings`.
- Manual checks: add the widget from the desktop, see the photos appear after opening the app, click a memory photo and a library photo, switch accounts, sign out, and click the empty widget with the app quit.
