# Viewer

View menu and toolbar actions open a separate native macOS full-screen window. Escape or Exit Full Screen closes it and leaves the current item selected in the original grid. Full-screen controls hide after 2.5 seconds without pointer movement, unless the pointer is over the controls or settings are open.

Start Slideshow uses multiple selected assets in grid order. Without a multiple selection, it follows the current collection, lazily loading adjacent buckets/pages. Shuffle loads collection metadata before building a shuffled sequence and an ID-to-index map. This costs O(n) memory and an initial O(n) load; subsequent sequence lookup is O(1). Large-library lazy bucket shuffling remains a future improvement. The settings popover offers a persistent interval, shuffle, fade/none, and a video time limit. Space pauses/resumes, arrows navigate. Videos normally finish before advancing. Playback failure advances immediately; 30 seconds without playback progress also advances, even when the video time limit is off. Repeating a single selected video restarts its player. Ordered collection playback pauses at the end; explicit selection/shuffle sequences repeat. Display sleep is inhibited while an unpaused slideshow runs, and the cursor hides with idle controls. Native video controls remain available, with persistent mute/volume and a playback-speed/loop menu. Slideshow completion takes precedence over video looping.

Edit offers Copy Image with Command-C handled by the focused grid/viewer, leaving text-field copying to the native responder, Copy Original Image, and Copy as File. Preview images use the existing image cache; original image copy downloads to a temporary file and decodes via ImageIO without buffering the compressed original as Data or applying the zoom pipeline's downsampling. File copy downloads into the app's temporary directory and publishes a file URL for Finder or other apps. Only the latest copy is retained, until the next copy or app launch.

View-only rotation is in View, without a keyboard shortcut. Rotation resets when navigating. No image or metadata is changed on the server. Show in All Photos works from View and grid context menus. It loads the target timeline month, switches to Library, selects the asset and scrolls to its cell. Assets excluded from the main timeline, including non-primary stack members, produce an explanatory message.

Neighbour preview prefetching uses the slideshow sequence for selection/shuffle and the grid order otherwise, through the existing pipeline. Face overlays belong to the People feature. Optional filmstrips were omitted.

## Protocol and platform references

Checked the v3.3.5 OpenAPI document at https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json:

- POST /auth/login, LoginCredentialDto and LoginResponseDto.
- GET /assets/{id}, AssetResponseDto, originalFileName and localDateTime.
- GET /assets/{id}/thumbnail, size=preview, authenticated binary response.
- GET /assets/{id}/original, authenticated original binary response.
- GET /assets/{id}/video/playback, authenticated video/range playback.
- GET /timeline/buckets and /timeline/bucket, timeBucket, visibility, withPartners and withStacked; TimeBucketsResponseDto and columnar TimeBucketAssetResponseDto.

Cross-checked https://api.immich.app and https://immich.app/docs, and official v3.3.5 web sources SlideshowBar.svelte, SlideshowSettingsModal.svelte, slideshow.store.ts and slideshow-history.ts. These establish persisted timing/transition/order controls, idle hiding, pause and navigation behavior. No upload or sync code is involved.

Apple documentation checked: NSWindow.toggleFullScreen, NSPasteboard.writeObjects, AVPlayer playback/rate/volume/KVO, SwiftUI onContinuousHover and NSHostingView, with macOS availability covered by the deployment target. The full-screen API is available since macOS 10.7. No new framework dependency is needed.

No new server endpoints or feature flags are required. The feature reuses existing v2-compatible media and timeline APIs. Missing/unauthorized resources produce errors rather than enabling any server mutation. Full compatibility with every v2 server was not tested.

## Verification

Debug xcodebuild completed successfully. No new compiler warnings; Xcode emits its standard AppIntents metadata-skipped warning because this app has no AppIntents dependency. git diff --check passes.

Read-only demo.immich.app checks logged in with the public demo account, fetched timeline buckets, a columnar bucket, asset detail, preview and original bytes, and decoded the JSON with the unmodified production Models.swift DTOs. Preview was 161164 bytes and original was 1779462 bytes at test time. A separate metadata search found a video; its playback endpoint returned HTTP 206, video/mp4, for a 1024-byte range. Both one-shot API sessions were logged out. The repeatable assertion check is scripts/check-viewer-responses.sh, accepting a directory of saved demo fixtures. It verifies column lengths, production DTO decoding, video type and ImageIO decoding of preview/original.

Before UI testing was prohibited, an isolated temporary harness explicitly created a demo-only ImmichClient and reused the production viewer/grid. It confirmed image display, native full-screen slideshow entry, Space changing Pause to Play, and idle control hiding. A window-reference error prevented a complete settings-popover check. No further UI runs were made after the user's stop instruction. Clipboard paste destinations, video playback controls, timeline scroll placement and the merged app's menus remain for the parent's single merged UI test.

An earlier ordinary app launch attached to a signed-in real-server Library. Only the UI tree was inspected there. Automatic restore/library reads may have occurred; no server write, edit, delete, favorite or other mutation was invoked. Both ImmichGallery and the isolated ViewerSmoke process were terminated when the stop instruction arrived, and pgrep confirmed neither remained. No Keychain credentials were read by scripts or extracted.

## Review-fix verification

The review fixes are checked by Debug xcodebuild and `scripts/check-viewer-state.py`, which compiles the production navigation and window-close methods into an isolated assertion executable with an in-memory grid. It does not launch ImmichGallery, create windows, read credentials, access the clipboard, or contact any server. It covers presentation Space/Return/Escape handling, wraparound and prefetch order, coalesced navigation during an async load, same-item video restart generation, boundary pause, close cleanup and preserved selection.

Presentation menu routing also uses the NSWindow delegate's key-window state, since an NSHostingView has no SwiftUI Window scene. Command-C is attached to focused view content rather than a global menu shortcut and explicitly rejects text responders. These UI paths, cursor behavior and AVPlayer failure behavior were inspected and compiled; interactive verification remains deferred under the no-launch instruction.
