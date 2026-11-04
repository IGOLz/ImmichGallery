# Asset management and utilities

Implemented in the Assets API extension, DTOs, downloader, and views.

- Grid context menu: stack multiple selected assets and download selected assets as ZIP. Stack badges use the existing columnar timeline data and the new optional asset stack summary for search responses.
- Viewer: Browse Stack opens a member browser with image/video previews, member thumbnails, Set Primary, Remove from Stack, and confirmed Unstack. Unstacking preserves library assets.
- Toolbar Asset Utilities menu: selected-assets ZIP export, whole-album ZIP export, bulk coordinate entry, or Recently Deleted actions. Restore All and Empty Trash confirm their full-library scope. Trash retention days are loaded from server/config.
- Utilities sidebar: Duplicates appears only with duplicateDetection enabled; Large Files shows the official web client's largest-files results with byte-size badges; Assign Location opens the timeline with the bulk location action. Coordinate entry checks finite values and geographic ranges before sending PUT /assets.
- Duplicate groups show side-by-side previews, sizes, Keep toggles, suggested defaults, confirmed keep/trash resolution, and confirmed dismiss. Resolution checks bulk response success. Keep/trash is disabled when the server disables trash, avoiding unintended permanent deletion.
- ZIP archives use the account's download.archiveSize preference. POST /download/info determines parts and motion assets. The server includes Live Photo videos and respects includeEmbeddedVideos for embedded Android motion parts. Each returned part streams through URLSession's download API into a temporary file, reports byte progress, and moves to a unique file in the chosen folder. HTTP errors never become saved ZIP files; completed parts survive later-part failure.

## Contracts and documentation

Checked the v3.3.5 OpenAPI spec at https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json for stacks and member removal, download/info and download/archive, duplicates and duplicates/resolve, trash/empty and trash/restore, server/features and server/config, users/me/preferences, search/large-assets, and PUT /assets.

Checked https://api.immich.app and the official v3.3.5 web/source files:

- web/src/lib/services/stack.service.ts and trash.service.ts
- web/src/lib/utils/asset-utils.ts and web/src/lib/managers/download-manager.svelte.ts
- web/src/routes/(user)/utilities/duplicates/.../+page.svelte
- web/src/routes/(user)/utilities/large-files/.../+page.ts and +page.svelte
- web/src/routes/(user)/utilities/geolocation/+page.svelte
- server/src/services/download.service.ts
- server/src/repositories/asset.repository.ts: withStacked=true collapses stacks to their primary and emits [stackId, count]. Existing timeline behavior is retained.
- docs/docs/features/duplicates-utility.md: resolution merges metadata when exactly one asset is kept.

The public documentation URLs failed to load through the web tool, so the matching official tagged documentation was read from GitHub. Apple documentation for NSOpenPanel, confirmationDialog and URLSession.download(for:delegate:) was checked; download's async API requires macOS 12 and is available on the macOS 26 target.

## Compatibility and deliberate limits

New stack summaries and suggestedKeepAssetIds are optional for older responses. Duplicates is hidden when the feature flag is missing/false. Unsupported duplicate or stack reads handle 404 without crashing. Other unsupported endpoints show a recoverable error. search/large-assets is deprecated in 3.2 but is the endpoint used by the v3.3.5 web utility and was stable in v2. Duplicate resolution and member removal target v3.3.5; older servers may reject those actions. No substitute deletion is attempted.

There is no "without location" filter in the v3.3.5 web utility: its geolocation page shows the timeline and assigns locations. This implementation follows that scope with coordinate entry, leaving richer map UX to the Metadata feature. No duplicate auto-resolve-all, automatic stacking of kept duplicates, or metadata synchronization is implemented locally; the dedicated resolve endpoint supplies the server's merge semantics.

## Verification

Debug xcodebuild succeeded with no Swift warnings. The existing AppIntents metadata-extraction warning remains because the project has no AppIntents dependency.

Read-only checks against demo.immich.app confirmed v3.3.5, decoded 129 duplicate groups and 250 large assets with the production Swift DTOs, decoded preferences/features/config/download plans, and downloaded two split ZIP parts (13,695 and 11,062 bytes) that passed ZIP integrity checks. Tests/AssetsDTOCheck.swift is an assert-based decoder check; compile it with API/Models.swift and API/Models+Assets.swift and supply captured JSON files named duplicates.json, large.json, download.json, preferences.json, config.json, and features.json. It also checks synthetic stack embedding of a real asset and missing older-server suggested IDs.

The demo rejected uploading unique generated PNG fixtures with HTTP 403 before creating any asset. Stack create/update/remove/delete and location mutations therefore could not be live-tested without modifying someone else's data; none were performed. No fixtures were created or left behind. Empty-trash, restore-all, and duplicate mutations were verified only against the spec and official source, as required. Launch was attempted with open; screen capture did not show this app, so interactive UI behavior is unverified.
