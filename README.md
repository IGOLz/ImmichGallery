# ImmichGallery
Independent open-source macOS photo gallery client for Immich. Early development.

A native SwiftUI app for macOS that browses your [Immich](https://immich.app) library with an Apple Photos–style interface.
Not affiliated with the Immich project.

## Features (v0.0.1)

- Sign in with email & password (session token) or an API key; server discovery via `/.well-known/immich`, the same way the official mobile app does it
- Library timeline grouped by month, with ThumbHash placeholders and lazy per-month loading (`/timeline/buckets` + `/timeline/bucket`)
- Favorites, Videos, Archive, Recently Deleted, Albums, People
- Smart (CLIP) search, or file-name search when smart search is off on the server
- Viewer: arrow-key navigation, pinch/double-click zoom (loads the original when you zoom in), video playback, Live Photos
- Info inspector (⌘I): camera, exposure, size, location map, people, albums
- Favorite (`.`), archive, delete/restore (⌘⌫), Export Unmodified Original (⇧⌘E)
- Credentials are stored in the Keychain, and images are cached on disk

## Requirements

- macOS 26 or later
- Xcode 26 or later
- An Immich server, v2.0 or later (tested against v3.3)

## Build

```sh
open ImmichGallery.xcodeproj         # then ⌘R
# or
xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/ImmichGallery.app
```

The project uses Xcode's folder-synced groups. Any file you add under `ImmichGallery/` is picked up automatically.
Debug builds are signed ad hoc ("Sign to Run Locally"). To sign with your own identity, set a team in *Signing & Capabilities*.
With ad-hoc signing, macOS may ask for Keychain access again after each rebuild.

To try it without your own server, use the public demo at `demo.immich.app` (`demo@immich.app` / `demo`).

## Project layout

```
ImmichGallery/
  API/        ImmichClient (REST + discovery), DTOs
  App/        App entry & menus, session state, grid model
  Support/    Image pipeline, ThumbHash decoder, Keychain, formatters, export
  Views/      Login, sidebar/main, grid, viewer, inspector, albums, people, settings
Config/       Info.plist (ATS for http LAN servers), entitlements (sandbox)
```

## Releasing

`scripts/release.sh` archives the app with your Developer ID certificate, notarizes and staples it, and writes a DMG and a zip to `build/release/`:

```sh
NOTARY_PROFILE=my-profile scripts/release.sh
# or, with an App Store Connect API key:
NOTARY_KEY=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer-id> scripts/release.sh
```

Bump `MARKETING_VERSION` in the project before releasing.
