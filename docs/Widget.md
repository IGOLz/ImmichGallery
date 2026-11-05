# Desktop widgets

WidgetKit widgets in the style of Apple Photos. Since 0.4.1 each source is its own widget, so the widget gallery lists them all:

- **Photo widgets** (small to extra large) show one photo at a time and change it every hour. There is one widget for each source:
  - **Featured Photos**: today's memories, then random photos. Its kind is `FeaturedPhotos`, the 0.3.1 kind.
  - **Favorites**.
  - **Album**, **Person** and **Place** (city). *Edit Widget* chooses which album, person or place. Until the user chooses, they show the most recently updated album, the person with the most photos and the most recently visited place, so a new widget shows photos right away.
  - **Chosen Photos**.
- **Photo Mosaic** (medium 3, large 4, extra large 6 photos) shows several photos at once, each clickable. *Edit Widget* chooses any of the sources above (`PhotoWidgetIntent`).

In 0.4.0, `FeaturedPhotos` was a single configurable widget. Widgets of that kind now show Featured whatever they were set to.
- **Library** (small, medium): photo, video, album and people counts, the library's size and the server's storage.

The photo widgets have a **Next Photo** button (an interactive `Button(intent:)`). It advances that source's position (the mosaic keeps its own), and the hourly rotation continues from there. **Chosen Photos** come from **Show in Widget / Remove from Widget** in the photo context menu and the Image menu (up to 50 photos, newest first, kept per account).

## How it works

- **The app prepares everything.** `WidgetFeedUpdater` writes `feed.json` and `images/<assetID>.jpg` (previews downscaled to 1280 px JPEGs) to `<App Group container>/Widget`. `feed.json` holds:
  - one pool of photos per source (up to 24; all chosen photos);
  - the catalog the widget's configuration lists: albums, named people, cities;
  - the library statistics;
  - a SHA-256 of the account, never the account itself.
- **Pools.** Featured uses today's memories (at most 4 per memory, half the pool, only if memories are enabled), then `POST /search/random`. The other sources use `search/random` with `isFavorite`, `albumIds`, `personIds` or `city`. Chosen photos use `GET /assets/{id}`, and a photo drops out only on a 404. Previews already on disk are reused across pools.
- **Which pools.** The app builds pools for the sources the installed widgets show. It reads each widget's kind and `WidgetCenter` configuration (`AlbumWidgetIntent`, `PersonWidgetIntent`, `PlaceWidgetIntent`, `PhotoWidgetIntent`) and, because the app can't always resolve an album or person entity from a configuration, also reads the sources the widgets' timeline providers noted in the App Group defaults (`requested`) in the last two days. If no widget of the app is installed, or WidgetKit can't say, nothing is fetched.
- **Refresh.** It runs on sign-in and account switch, when the app becomes active, every hour while the app runs, and when a widget has no photos for its source. In that last case, a widget just added or set to another album posts the Darwin notification `<App Group>.widget-needs-photos`, and the running app, even in the background, prepares the photos within seconds. A refresh asked for while one is running runs again when it ends:
  - a pool is rebuilt when it is from another day, older than 6 hours, or the chosen photos changed;
  - the catalog and statistics are rebuilt every hour;
  - on network errors, or when every preview fails, the previous pool stays;
  - unused previews and 0.3.1's files are removed.

  When the app doesn't run, the widgets keep cycling through the last pools.
- **Accounts.** Switching accounts removes the previous account's data at once. Signing out deletes it.
- **Widget states.** A widget whose source has no pool yet says *Open Immich Gallery to load these photos*. This only lasts when the app isn't running; clicking opens the app, which then fills the widget. In the widget gallery, previews show any photo the app already prepared.
- **Clicks.** A memory photo opens `immichgallery://memory/<id>` (the memory player). Other photos open `immichgallery://photo/<id>` (a photo window, `WidgetPhotoScene`). Empty states, the Library widget and the mosaic's edges open `immichgallery://open`, which shows a library window. `MacIntegrationLifecycle` handles the URL Apple event directly, so SwiftUI doesn't open an extra library window for each click, and the account is restored at launch even without a library window. Only UUIDs are accepted, because any web page can open the scheme.
- **Shared code.** `Shared/WidgetFeed.swift` (kinds, files, rotation, links, the notification) and `Shared/WidgetIntents.swift` (the configuration intents and their defaults, the album/person/place entities and their queries, `NextPhotoIntent`) are compiled into both targets. The app needs the intent types to read configurations. All the intents are `isDiscoverable = false`, so they don't show up in Shortcuts.

## App Group and signing

The group is `$(TeamIdentifierPrefix)dev.igol.ImmichGallery`. It is the `IMMICH_APP_GROUP` build setting, which is used in both entitlements files and in the `ImmichAppGroup` key of both Info.plist files.

- **Release builds** (`scripts/release.sh`, which sets `DEVELOPMENT_TEAM`) get `884UZN5CH3.dev.igol.ImmichGallery`. A team-prefixed group works with Developer ID on macOS 15 and later without a provisioning profile, and its `UserDefaults` suite holds the Next Photo positions and the requested sources.
- **Local ad-hoc Debug builds** have no team, so the group has no prefix. macOS may then ask for permission to access data from other apps, or block the container. Sign Debug builds with the team to try the widgets.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the project-level build settings, so the app and the extension always match.

## Verification

- `xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build`. The `.appex` is embedded in `Contents/PlugIns`, and its `Metadata.appintents` lists the four configuration intents, `NextPhotoIntent`, the three entities and `WidgetPhotoSource`.
- `python3 scripts/check-mac-localization.py` checks the widget's strings against the widget's own catalog (`ImmichGalleryWidget/Localizable.xcstrings`), which is all the extension can read at run time.
- Manual checks:
  - add each widget and set each source, and see photos after opening the app;
  - click a memory photo, a library photo, a mosaic tile and Next Photo;
  - use Show in Widget;
  - switch accounts and sign out;
  - click an empty widget with the app quit.
