# Native macOS integrations

Implemented for macOS 26 without new dependencies or targets. Since 0.2.0 the deployment target is macOS 15; `OSCompatibility.swift` provides the fallbacks.

- macOS 15 fallbacks: Liquid Glass becomes `.regularMaterial`; the toolbar's fixed spacer is omitted. The multi-item drag container (`dragContainer`, `dragContainerSelection`) is macOS 26 only, so on macOS 15 each grid cell drags an `NSItemProvider` (`legacyAssetDrag`) carrying the dragged photo's original as a file promise (named after the asset ID, since the real name is only known after the download) and the selected asset IDs. Album rows read those IDs from the drag pasteboard case-insensitively (AppKit lowercases the custom type) in one combined drop handler (`AlbumRowUploadDrop`), because macOS 15 delivers drops only to the innermost of two stacked drop targets. The viewer drags its single original on both systems.
- macOS 15 SwiftUI pitfalls found on a Sequoia VM in 0.2.1 (0.2.0 crashed or froze at 100% CPU):
  - A toolbar item must not bind a popover straight to an `@Observable` property, or read changing observable state in its own body. Put the changing parts in child views and use local `@State` for the popover (`UploadToolbar`, `AccountNotificationBell`, `ExploreMapFiltersButton`).
  - Don't disable a whole popover with `.disabled(busy)` while it becomes key; it loops in AttributeGraph.
  - Toolbar items attached to the `NavigationSplitView` combined with a pushed page's own toolbar loop forever. On macOS 15 the global items live on the detail `NavigationStack` (`GlobalToolbar`), and the grid's zoom buttons aren't a `ControlGroup`.
  - An `AVPlayerView` draws above SwiftUI overlays; a sheet keeps the width it had while loading; a borderless `Menu` shows its own indicator.

- On macOS 26+ each grid cell has a single drag source, `OriginalTransfer`: the original file first (generic data, real filename from the download), then the original-drag marker and, outside the Locked Folder, the asset's own ID for album drops. A container drag yields one item per selected asset; album rows merge their IDs in order without repeats. A second `draggable` of the asset IDs alone used to compete with the file, and the Finder saved that JSON as "Immich Gallery Asset Selection" (#44). `Tests/OriginalDragChecks.swift` (in `scripts/check-integration.py`) loads real item providers offline: representation order, original bytes and filename, same-named originals, album IDs, failed downloads and Locked Folder revocation. Finder drops still need a manual UI check.
- Internal grid and viewer drags carry an original-drag marker alongside their file promise. Upload targets reject that marker and the album asset-ID type before highlighting or loading file URLs, including when AppKit lowercases the pasteboard types. macOS 15 viewer drags use the explicit item provider to preserve the marker. Album asset drops still use the existing selected IDs. `Tests/UploadDropChecks.swift` checks internal markers, file-only provider fallback through the pasteboard, and external file eligibility without loading contents.

- Drag promises download originals on demand. Downloads use the response's suggested filename, strip path components, map HTTP 401 to the session-expired error, and clean up failed moves. Receivers may access the original temporary file in place, avoiding the previous forced second copy. Files expire after ten minutes; cleanup runs on startup, every minute, and termination. Preview files have a separate directory and remain leased while Quick Look uses them. Cleanup also handles the previous cache layout.
- Space previews selected items in grid order, with a maximum of 20 originals. Quick Look opens when the first original arrives and adds the others as they finish. Space during downloads cancels them. The originating window is captured before downloading. Return and double-click still open the viewer.
- AppModel owns one AccountServices for the signed-in account. Windows create a thin LibrarySession lazily, keyed by service identity. Bootstrap and notification polling run once per account. Pipeline, uploads, preferences and sharing data are shared; navigation, selection and presentations are per window. Commands resolve the active window through FocusedValues.librarySession. See Integration.md for integration verification.
- Album menus offer new windows and tabs. Scene windows get a common tabbing identifier; tab routes use native preferred tabbing rather than polling arbitrary NSApp windows. Command-T and Show Tab Bar are available.
- Search Photos and Open Album require a saved account through the small MacIntentAccount helper. Routes form a queue handled by the app's scene even when no library window exists. Sign-out clears the queue. Intent routing does not wait for bootstrap.
- Export completion always reveals saved files in Finder, including while the app is inactive. SystemNotifier is also available for opt-in background notifications. Denied notification permission shows a System Settings hint.
- Italian strings include explicit singular/plural forms in English and Italian, including separate substitutions for exported and failed counts. Archive's sidebar noun remains "Archivio"; its action uses "Archivia". Tabs use "scheda". Reviewed library, favorites, info, export, archive and recently deleted terminology.

## Transfer type and viewer gestures

The installed CoreTransferable SDK requires a static exportedContentType in FileRepresentation. Grid timeline DTOs provide no original filename or MIME type, so a truthful per-item UTType cannot be derived before the drag without additional metadata requests. Promises now advertise generic file data, preserving the actual filename/extension from Content-Disposition, instead of advertising all RAW/HEIC files as image or all videos as movie. Receivers requiring an exact pre-advertised UTType still need a future metadata-backed NSFilePromiseProvider implementation. No speculative type is assigned.

The viewer's drag source is attached to the displayed image, not its container or navigation controls. It is disabled above 1× zoom; the pan gesture is enabled only when zoomed. Videos retain their own drag source.

Zoomed photos also pan with two-finger trackpad scrolling, including momentum, in the inline and presentation viewers. `ViewerScrollPan` consumes native scroll deltas on both axes only inside the visible photo viewport in its own window while zoomed. At 1×, events pass through so the inline viewer can scroll to photo details. `Tests/ViewerScrollPanChecks.swift` covers both axes, event consumption, pointer/window scope, zoom reset and detached views. The updated Dev app was built, installed and opened; automated UI scrolling confirmed vertical panning and scrolling to details after resetting zoom. Physical trackpad gestures and horizontal UI movement remain manual checks; the automation produced no visible horizontal movement.

## Verification for review fixes

The required Debug command was run without launching the app:

```
xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build
```

Build succeeded with no warnings. Local logs and binaries remain ignored under build/.

- `python3 scripts/check-mac-localization.py`: checks extracted strings, catalog coverage and format placeholders, including plural substitutions.
- `swift scripts/check-mac-plurals.swift`: reads compiled localization resources, checks singular/plural output with different selected/total and exported/failed counts, and distinguishes archive noun/verb. It does not run the app executable.
- `scripts/check-mac-transfer-cache.swift`: compiled against the real API extension and checks fresh/expired drag files, leased previews, release and legacy cleanup in an isolated temporary directory. No network or Keychain access.
- Inspected Debug's generated `Metadata.appintents/extract.actionsdata`: both SearchPhotosIntent and OpenAlbumIntent, their parameters and both shortcuts are present with this Xcode toolchain. The reported Release-only extraction issue does not reproduce; no ENABLE_DEBUG_DYLIB or project-file change is needed.

No live server was contacted, no Keychain item was read, and no app was launched during this review-fix pass. Finder drops, Quick Look rendering, native tab attachment, no-window Shortcuts routing and notifications remain manual checks for the parent's single merged app. Do not launch individual worktree builds: they share the app bundle ID and saved account.

## Deliberate omissions

Widgets are covered in `Widget.md`. A menu bar extra and unattended export intent remain outside this change. No project settings were changed by the review fixes.

## Locked Folder

Unlocked grids use a separate `LibrarySession` backed by `LockedFolderMedia`, an uncached client and a memory image cache. Quick Look, drag and clipboard originals use a per-unlock directory under `MacTransferCache.lockedRoot`. Locking revokes that directory before deleting it, preventing late downloads from recreating files. Copied content is cleared only while it still owns the pasteboard. Files are also removed at quit and at the next launch.

Locking clears all windows sharing the account session. Screen lock, sleep, leaving the page and the Lock button lock immediately. Switching to another app allows a 15-minute grace period, enforced locally because background notification polling can extend the server unlock. Returning after that deadline still locks before cancelling the inactivity timer.
