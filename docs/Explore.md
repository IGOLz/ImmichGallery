# Explore implementation and verification

Targets Immich v3.3.5 and macOS 26. README and project.pbxproj were not edited.

## Features

- Map sidebar with SwiftUI Map, photo-cover clusters, counts, favorites, archived, partner and inclusive date-range filters. Camera changes regroup markers off the main actor into bounded geographic cells. Cluster selection opens the existing grid/viewer, fetching full asset details in batches of at most eight requests and pages of 100 assets.
- Places uses representative photos from search/cities, with city metadata search on selection.
- Memories respects memories.enabled and opens a separate full-window player with timed preview slides, pause, arrows, keyboard controls, seen state, hide and removal of individual memory associations. Both on_this_day and birthday titles decode; unknown future types still decode.
- Tags respects tags.enabled, supports full hierarchy paths through upsert, browsing with timeline tagId, rename, hex recolor/clear, confirmed deletion, and assignment/removal for selected assets through the grid context menu.
- Folders respects folders.enabled and builds a deduplicated expandable path tree. Selection loads direct children through view/folder.
- Locked Folder checks auth status, supports six-digit PIN setup with confirmation, unlock and lock, pages locked assets, and moves assets back to the timeline. Normal grid context menus move selected assets into the locked folder. Locked media uses a separate ephemeral client and never enters the common grid/viewer or image cache. The view clears media on disappearance/inactivity and requests server relocking. Failures to relock are surfaced.

## Privacy and integration

The image pipeline now uses an ephemeral media session for ALL image loads. This intentionally gives up disk thumbnail caching because an in-flight ordinary thumbnail request could otherwise write to disk after an asset is moved into Locked Folder. Existing URLCache entries are purged when a pipeline is created. The memory NSCache remains for ordinary photos. Moving photos into Locked Folder immediately removes them from every cached grid, selection and viewer, and clears image caches. Metadata results filter locked visibility. The v3.3.5 timeline's default visibility includes only timeline/archive, confirmed in server/src/utils/database.ts.

Touch ID is deliberately omitted: this implementation never stores the PIN. Locked videos and Live Photos currently show preview stills, without AVPlayer or export, to keep locked media out of uncontrolled disk caches. Memory videos also use preview slides. An independent video playback/cache design remains needed for those views.

Map and Places depend on the server's map flag where applicable. Preferences must explicitly enable Memories, Tags and Folders. Locked Folder is hidden when auth/status is unavailable. Endpoint failures render unavailable/error states rather than crashing. v3.3.5 deprecated PUT tag/memory updates remain supported and retain compatibility with v2. Missing preference sections hide their respective features. No v2 server was available for runtime verification.

## Documentation checked

- https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json, downloaded once into ignored build/explore/spec.json. Checked map/markers query names, search/cities, search/metadata, timeline tagId, all tags endpoints and DTOs, memories query/types/update/assets, view/folder endpoints, users/me/preferences, auth/status, auth/pin-code, auth/session/unlock and lock.
- https://api.immich.app and https://docs.immich.app/features/tags/.
- Official v3.3.5 web Explore, Folders, Locked and Memories routes; timeline and asset-viewer SetVisibilityAction, PIN creation form. Server timeline.service.ts, asset.repository.ts, search.repository.ts and utils/database.ts confirmed default visibility and city selection.
- Apple Map, NSViewRepresentable, ScenePhase and URLSessionConfiguration.ephemeral references, including the downloadable Apple documentation Markdown. Actual implementation uses SwiftUI Map and native SwiftUI windows, not an AppKit map wrapper.

## Verification

xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build

Build succeeded. No Swift compiler warnings. Xcode prints its existing AppIntents metadata warning because the app has no AppIntents dependency.

Standalone checks, using actual production clustering/tree/DTO definitions:

swiftc -parse-as-library ImmichGallery/API/Models.swift ImmichGallery/API/Models+Explore.swift ImmichGallery/App/ExploreClustering.swift ImmichGallery/App/ExploreFolders.swift Tests/ExploreChecks.swift -o build/explore/checks
build/explore/checks

Passed preference optionality, auth elevation, folder hierarchy/deduplication, 50,000-marker bounded clustering and international date-line visibility checks.

Live script checks used ONLY https://demo.immich.app with a newly obtained demo account token:

- Swift decoded real responses: 969 map markers, 149 representative city assets, 40 memories, 4,779 tags, 25,964 folder paths, preferences and auth status.
- Map filters with date bounds/favorites/partners returned four markers; city search, direct folder search and tag timeline buckets succeeded.
- Created a uniquely named parent/child tag hierarchy; renamed, recolored and cleared color; deleted both test tags successfully.
- Created a temporary memory, marked it seen, removed its photo association, and deleted the memory. The referenced existing photo was never modified.
- Attempted a tiny generated test-image upload for tag-assignment verification; demo returned HTTP 403 before creating an asset. Tag assignment/removal were therefore checked against spec and source, not mutated on shared photos.
- Demo memories.enabled was false; settings were not changed. Demo already had a PIN. PIN setup/unlock/lock and locked-asset mutations were NOT attempted on the demo.

One local app copy was launched before the parent announced that all worktrees share the bundle ID and Keychain. No UI actions were performed. It may have automatically made read-only startup requests to the user's real server through restored credentials; this was not observed or verified. No write call to the user's server was initiated. The process had already exited when instructed to quit; a process-list check confirmed no copy from this worktree remained. No further UI runs were made. Authenticated feature UI remains unverified and is reserved for the parent's single merged build. No credentials were read from Keychain by tooling.

## Shared-file changes

- API/ImmichClient.swift: optional TimelineQuery.tagId and query encoding.
- App/AssetGridModel.swift: Explore source routing/pagination, immediate removal of sensitive assets, filter locked metadata results.
- App/AppModel.swift: remove selected IDs from all cached grids.
- App/ImmichGalleryApp.swift: one ExploreMemoryScene insertion.
- Views/MainView.swift: Explore SidebarItem case, detail routing and sidebar section insertion.
- Views/Grid/AssetGridView.swift: one ExploreAssetActions context-menu insertion.
- Support/ImagePipeline.swift: ephemeral media client and purge of old shared URLCache entries.
