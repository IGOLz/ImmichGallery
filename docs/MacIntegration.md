# Native macOS integrations

Implemented for macOS 26 without new dependencies or targets. Since 0.2.0 the deployment target is macOS 15; `OSCompatibility.swift` provides the fallbacks.

- macOS 15 fallbacks: Liquid Glass becomes `.regularMaterial`; the toolbar's fixed spacer is omitted. The multi-item drag container (`dragContainer`, `dragContainerSelection`) is macOS 26 only, so on macOS 15 each grid cell drags a `LegacyAssetDrag` that carries the dragged photo's original (for the Finder) and the selected asset IDs (for album drops). The viewer drags its single original on both systems.

- Drag promises download originals on demand. Downloads use the response's suggested filename, strip path components, map HTTP 401 to the session-expired error, and clean up failed moves. Receivers may access the original temporary file in place, avoiding the previous forced second copy. Files expire after ten minutes; cleanup runs on startup, every minute, and termination. Preview files have a separate directory and remain leased while Quick Look uses them. Cleanup also handles the previous cache layout.
- Space previews selected items in grid order, with a maximum of 20 originals. Quick Look opens when the first original arrives and adds the others as they finish. Space during downloads cancels them. The originating window is captured before downloading. Return and double-click still open the viewer.
- AppModel owns one AccountServices for the signed-in account. Windows create a thin LibrarySession lazily, keyed by service identity. Bootstrap and notification polling run once per account. Pipeline, uploads, preferences and sharing data are shared; navigation, selection and presentations are per window. Commands resolve the active window through FocusedValues.librarySession. See Integration.md for integration verification.
- Album menus offer new windows and tabs. Scene windows get a common tabbing identifier; tab routes use native preferred tabbing rather than polling arbitrary NSApp windows. Command-T and Show Tab Bar are available.
- Search Photos and Open Album require a saved account through the small MacIntentAccount helper. Routes form a queue handled by the app's scene even when no library window exists. Sign-out clears the queue. Intent routing does not wait for bootstrap.
- Export completion always reveals saved files in Finder, including while the app is inactive. SystemNotifier is also available for opt-in background notifications. Denied notification permission shows a System Settings hint.
- Italian strings include explicit singular/plural forms in English and Italian, including separate substitutions for exported and failed counts. Archive's sidebar noun remains "Archivio"; its action uses "Archivia". Tabs use "scheda". Reviewed library, favorites, info, export, archive and recently deleted terminology.

## Transfer type and viewer gestures

The installed CoreTransferable SDK requires a static exportedContentType in FileRepresentation. Grid timeline DTOs provide no original filename or MIME type, so a truthful per-item UTType cannot be derived before the drag without additional metadata requests. Promises now advertise generic file data, preserving the actual filename/extension from Content-Disposition, instead of advertising all RAW/HEIC files as image or all videos as movie. Receivers requiring an exact pre-advertised UTType still need a future metadata-backed NSFilePromiseProvider implementation. No speculative type is assigned.

The viewer's drag source is attached to the displayed image, not its container or navigation controls. It is disabled above 1× zoom; the pan gesture is enabled only when zoomed. Videos retain their own drag source. Gesture behavior still needs manual UI verification.

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

Widgets require another target, an App Group and a credential/signing design, so they remain omitted. A menu bar extra and unattended export intent remain outside this change. No project settings were changed by the review fixes.
