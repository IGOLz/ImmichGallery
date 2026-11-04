# ImmichGallery
Independent open-source macOS photo gallery client for Immich. Early development.

A native SwiftUI app for macOS that browses your [Immich](https://immich.app) library with an Apple Photos–style interface.
Not affiliated with the Immich project.

## Features

**Library and viewer**
- Sign in with email & password (session token) or an API key; server discovery via `/.well-known/immich`, the same way the official mobile app does it
- Library timeline grouped by month, with ThumbHash placeholders and lazy per-month loading (`/timeline/buckets` + `/timeline/bucket`)
- Favorites, Videos, Archive, Recently Deleted (with Empty Trash / Restore All), Albums, People
- Viewer: arrow-key navigation, pinch/double-click zoom (loads the original when you zoom in), video playback with loop/speed/volume memory, Live Photos, native full screen, slideshow (interval, shuffle, fade), copy image (⌘C), temporary rotation, Show in All Photos
- Info inspector (⌘I): camera, exposure, size, location map, people, albums
- Favorite (`.`), archive, delete/restore (⌘⌫), Export Unmodified Original (⇧⌘E), ZIP download of a selection or an album

**Organize and edit**
- Import (⇧⌘I) of files and folders, or drag & drop onto the window or an album; duplicate check by SHA-1, background queue with progress, cancel and retry
- Albums: create (⌥⌘N, also from a selection), rename, description, cover, sort order, add/remove photos (also by dragging onto the sidebar), delete; share with users (editor/viewer), comments and likes
- Metadata: date and time (single or bulk shift, with time zones), location from a map, description, star rating, non-destructive rotate (⌥⌘R / ⇧⌥⌘R) and crop
- People: person pages, rename, birthday, hide, favorite, merge, featured photo; face boxes in the viewer, assign or remove faces
- Stacks, duplicate review, large files, assigning a location to photos that have none

**Discover and share**
- Advanced search (⌘F, filters ⌥⌘F): smart, file name, description and OCR modes; people, place, camera, date, type and rating filters; recent searches
- Explore: map with clusters, places, memories, tags, folders, PIN-protected Locked Folder
- Public shared links (expiry, password, download/upload permissions), partner sharing, macOS share sheet

**Account and administration**
- Several accounts and servers with an account switcher; profile, password, API keys, sessions, notifications, server-side preferences
- Administration window for admins (⌥⌘A): statistics, jobs, users, external libraries, read-only server settings

**macOS**
- Drag photos to the Finder or other apps, Quick Look with the space bar, several windows and tabs (⌘N, ⌘T), Shortcuts actions (Search Photos, Open Album), optional notifications when an export finishes
- English and Italian interface

Credentials are stored in the Keychain, and images are cached on disk per account. Notes on each area are in `docs/`.

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
  API/        ImmichClient (REST + discovery) and one extension + DTO file per feature
  App/        App entry & menus, AccountServices (per account) and LibrarySession (per window), grid model, feature state
  Support/    Image pipeline, ThumbHash decoder, Keychain, formatters, export, notifications
  Views/      One folder per feature: Login, Grid, Viewer, Inspector, Albums, People, Search, Explore, Sharing, Upload, Metadata, Assets, Account, Admin, MacIntegration, Settings
  Localizable.xcstrings   English and Italian strings
Config/       Info.plist (ATS for http LAN servers), entitlements (sandbox)
docs/         Notes on each feature area and on the multi-window architecture
scripts/, Tests/          Offline check scripts (`python3 scripts/check-integration.py`, `python3 scripts/check-mac-localization.py`)
```

## Releasing

`scripts/release.sh` archives the app with your Developer ID certificate, notarizes and staples it, and writes a DMG and a zip to `build/release/`:

```sh
NOTARY_PROFILE=my-profile scripts/release.sh
# or, with an App Store Connect API key:
NOTARY_KEY=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=<issuer-id> scripts/release.sh
```

Bump `MARKETING_VERSION` in the project before releasing.
