# Desktop widgets

Three WidgetKit widgets, in the style of Apple Photos:

- **Photos** (small to extra large): one photo at a time, changing every hour. *Edit Widget* chooses what it shows: **Featured** (today's memories, then random photos; the default), **Favorites**, an **Album**, a **Person**, a **Place** (city) or **Chosen Photos**. Its kind is still `FeaturedPhotos`, so widgets added in 0.3.1 keep working and show Featured.
- **Photo Mosaic** (medium 3, large 4, extra large 6 photos): the same sources, several photos at once, each clickable.
- **Library** (small, medium): photo, video, album and people counts, the library's size and the server's storage.

The photo widgets have a **Next Photo** button (an interactive `Button(intent:)`). It advances that source's position (the mosaic keeps its own), and the hourly rotation continues from there. **Chosen Photos** come from **Show in Widget / Remove from Widget** in the photo context menu and the Image menu (up to 50 photos, newest first, kept per account).

## How it works

- **The app prepares everything.** `WidgetFeedUpdater` writes `feed.json` and `images/<assetID>.jpg` (previews downscaled to 1280 px JPEGs) to `<App Group container>/Widget`. `feed.json` holds:
  - one pool of photos per source (up to 24; all chosen photos);
  - the catalog the widget's configuration lists: albums, named people, cities;
  - the library statistics;
  - a SHA-256 of the account, never the account itself.
- **Pools.** Featured uses today's memories (at most 4 per memory, half the pool, only if memories are enabled), then `POST /search/random`. The other sources use `search/random` with `isFavorite`, `albumIds`, `personIds` or `city`. Chosen photos use `GET /assets/{id}`, and a photo drops out only on a 404. Previews already on disk are reused across pools.
- **Which pools.** The app builds pools for the sources the installed widgets show. It reads `WidgetCenter` configurations and, because the app can't always resolve an album or person entity from a configuration, also reads the sources the widgets' timeline providers noted in the App Group defaults (`requested`) in the last two days. If no widget of the app is installed, or WidgetKit can't say, nothing is fetched.
- **Refresh.** It runs on sign-in and account switch, when the app becomes active, and every hour while the app runs:
  - a pool is rebuilt when it is from another day, older than 6 hours, or the chosen photos changed;
  - the catalog and statistics are rebuilt every hour;
  - on network errors, or when every preview fails, the previous pool stays;
  - unused previews and 0.3.1's files are removed.

  When the app doesn't run, the widgets keep cycling through the last pools.
- **Accounts.** Switching accounts removes the previous account's data at once. Signing out deletes it.
- **Widget states.** A widget whose source has no pool yet says *Open Immich Gallery to load these photos*, and clicking opens the app, which then fills it. An Album, Person or Place widget with nothing chosen asks to edit the widget.
- **Clicks.** A memory photo opens `immichgallery://memory/<id>` (the memory player). Other photos open `immichgallery://photo/<id>` (a photo window, `WidgetPhotoScene`). Empty states, the Library widget and the mosaic's edges open `immichgallery://open`, which shows a library window. `MacIntegrationLifecycle` handles the URL Apple event directly, so SwiftUI doesn't open an extra library window for each click, and the account is restored at launch even without a library window. Only UUIDs are accepted, because any web page can open the scheme.
- **Shared code.** `Shared/WidgetFeed.swift` (files, rotation, links) and `Shared/WidgetIntents.swift` (`PhotoWidgetIntent`, the album/person/place entities and their queries, `NextPhotoIntent`) are compiled into both targets. The app needs the intent type to read configurations. Both intents are `isDiscoverable = false`, so they don't show up in Shortcuts.

## App Group and signing

The group is `$(TeamIdentifierPrefix)dev.igol.ImmichGallery`. It is the `IMMICH_APP_GROUP` build setting, which is used in both entitlements files and in the `ImmichAppGroup` key of both Info.plist files.

- **Release builds** (`scripts/release.sh`, which sets `DEVELOPMENT_TEAM`) get `884UZN5CH3.dev.igol.ImmichGallery`. A team-prefixed group works with Developer ID on macOS 15 and later without a provisioning profile, and its `UserDefaults` suite holds the Next Photo positions and the requested sources.
- **Local ad-hoc Debug builds** have no team, so the group has no prefix. macOS may then ask for permission to access data from other apps, or block the container. Sign Debug builds with the team to try the widgets.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the project-level build settings, so the app and the extension always match.

## Verification

- `xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build`. The `.appex` is embedded in `Contents/PlugIns`, and its `Metadata.appintents` lists `PhotoWidgetIntent`, `NextPhotoIntent`, the three entities and `WidgetPhotoSource`.
- `python3 scripts/check-mac-localization.py` checks the widget's strings against the widget's own catalog (`ImmichGalleryWidget/Localizable.xcstrings`), which is all the extension can read at run time.
- Manual checks:
  - add each widget and set each source, and see photos after opening the app;
  - click a memory photo, a library photo, a mosaic tile and Next Photo;
  - use Show in Widget;
  - switch accounts and sign out;
  - click an empty widget with the app quit.
