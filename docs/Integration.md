# Integration review fixes

Implemented on `feature/web-parity`. No app launch, production-server calls, production Keychain access, push, or localization-catalog changes were made. Network access was limited to public source documentation. All executable regression tests used local fixtures or URLProtocol interception. The vault test used a generated test-only service and removed it afterward.

## Architecture

AppModel owns one AccountServices while signed in. It owns the client, user, capabilities, version, preferences, albums, tags, image pipeline, upload queue, sharing data, metadata work status/revisions, notification results/poller and a weak window registry. Bootstrap runs once per service lifetime. Restore callers await one stored task.

Each library window lazily creates a LibrarySession, keyed by AccountServices identity. The session owns its grids, navigation/selection through those grids, album presentations, metadata presentation/snapshot and sharing presentation. MainView publishes FocusedValues.librarySession; app and upload commands resolve the active window from it. Viewer commands retain their existing focused-viewer/full-screen context. Settings and Admin consume AccountServices. Memory windows create only thin presentation sessions and reset on account identity changes.

Account teardown cancels uploads/bootstrap/polling, closes viewers and Quick Look, requests Locked Folder relocking, purges the shared pipeline and clears queued intent routes. Switching and current-account removal use this path, as does sign-out. Intents require both the selected vault entry and the matching live AppModel account, checking again after album lookup.

## Findings

| Finding | Result |
| --- | --- |
| 1 | Fixed. Menu presentations and operations target the focused window; shared cache/queue/settings have no hidden library session. |
| 2 | Fixed. Intents use the selected vault entry, require a live matching account, and reject an account changed during lookup. No legacy-store fallback. |
| 3 | Fixed. One upload queue per account; common teardown cancels it on all transitions. |
| 4 | Fixed. One pipeline per account. Metadata/image revisions and person refreshes reach all windows. Locking removes assets from all grids, closes affected viewers/Quick Look and clears open memory images. |
| 5 | Fixed. AccountChrome hosts password-change UI and account errors above signed-in and signed-out roots. |
| 6 | Fixed. One restore task; concurrent restore regression assertion passes. |
| 7 | Delegated by the brief to the localization agent. Localizable.xcstrings remains untouched. |
| 8 | Fixed. Show in All Photos notifications carry the originating LibrarySession and listeners filter by it. |
| 9 | Fixed. Ownership/source gating covers mutation methods, menus, toolbar, viewer and stack controls. Location uses MetadataSheet; the second editor was deleted. Context exports share one Export submenu and the redundant selection ZIP toolbar entry was removed. Temporary rotation labels are explicit and remain in View commands. |
| 10 | Fixed. Memory sessions share services and reset with the account identity. |
| 11 | Fixed. Bootstrap and polling run once per account; window sessions initialize lazily. Explore sidebar preferences/capabilities come from shared services. Notification polling preserves error reporting/backoff. |
| 12 | Fixed. Image edits evict only their asset variants. Refresh invalidates grids/inspector without deleting disk cache. Explicit Clear Cache still purges the account cache and updates visible images. |
| 13 | Fixed. Preference changes increment shared preferencesRevision, refresh tags/sidebar preferences and reload sharing availability. |
| 14 | Fixed. Face overlays hide during temporary rotation and presentations; stack inset hides during presentations. The optional asset-details cache was omitted. |
| 15 | Fixed through common teardown and service-identity resets. |
| 16 | Fixed. Archive removal includes relevant utility/Explore grids while preserving archive-inclusive map/tag sources. Large-file and columnar timeline results exclude locked assets. Added empty-state titles, moved the enum case and corrected Favorite spacing. |
| 17 | Fixed. The tracked Account document and physical directory casing now use docs/. |

People updates remain NotificationCenter broadcasts because every window for the same account should react; their object is now AccountServices. Person-thumbnail notifications also include the affected person ID. This preserves the existing refresh behavior while excluding unrelated accounts.

Metadata image eligibility is loaded in MetadataHost's task outside the menu. The menu itself no longer relies on a task. Standard Edit Copy is not replaced; the image-copy key handler rejects NSText/NSTextField responders. Interactive responder-chain behavior still requires the parent's UI pass. Locked Folder now relocks on application resignation rather than another scene becoming inactive, and still relocks on leaving its view/account teardown.

## Source checks

- [Immich v3.3.5 OpenAPI](https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json).
- [Search service](https://github.com/immich-app/immich/blob/v3.3.5/server/src/services/search.service.ts) permits unspecified search visibility with elevated sessions. Client-side filtering therefore remains necessary.
- [Asset repository](https://github.com/immich-app/immich/blob/v3.3.5/server/src/repositories/asset.repository.ts) includes columnar visibility; it is now decoded and filtered as well as ordinary search and large-asset responses.
- [Web visibility action](https://github.com/immich-app/immich/blob/v3.3.5/web/src/lib/components/asset-viewer/actions/SetVisibilityAction.svelte) confirms locked/timeline bulk-update visibility semantics.
- Apple [FocusedValues](https://developer.apple.com/documentation/swiftui/focusedvalues), [focusedSceneValue](https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)), [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup) and [Commands](https://developer.apple.com/documentation/swiftui/commands) documentation was read, using its Markdown endpoints where the browser fetch required JavaScript.

## Verification

The required Debug xcodebuild succeeded after each logical implementation step, without new project-source warnings. No built app was run.

`python3 scripts/check-integration.py` compiles and runs 11 offline suites: metadata state, Admin refresh, paging/account services, sharing, uploads, Explore, person cache, search, metadata DTOs, transfer cache and album review. Tests cover shared pipeline/upload identity, independent window presentations, shared metadata revisions/sharing data, concurrent restore, ownership gating and locked columnar assets, alongside existing feature regressions. Harness compile inputs were updated for integrated DTO dependencies and the new AccountServices type.

Also passed:

- `python3 scripts/check-viewer-state.py`
- `python3 Tests/AccountVaultChecks.py`, unique disposable test service
- `python3 Tests/AccountImageChecks.py`
- `swift scripts/check-mac-plurals.swift`
- Sharing, People and Admin DTO suites compiled against all current API sources
- AssetsReviewCheck with the production download delegate extracted unchanged, offline mode
- AccountChecks compiled against current API sources and ran with synthetic local fixtures because the historical demo fixture directory was absent. Request contracts use URLProtocol and cache assertions use unique test IDs. Foundation printed cache-database diagnostics during disposable-cache removal; assertions passed.

`python3 scripts/check-mac-localization.py` remains blocked by incomplete catalog coverage, first reporting the existing “Move to Locked Folder” key. This belongs to finding 7 and was not repaired here.

## Strings for localization

Added or renamed: “Export”, “Download as ZIP…”, “Favorite (.)”, “Rotate View Temporarily Left”, “Rotate View Temporarily Right”, “No Partner Photos”, “No Large Files”, “No Photos to Locate”, “No Photos to Explore”. Other labels were reused. Removed the old AssetsLocationSheet-only text and redundant ZIP-selection toolbar label. No String(localized:) localization pass was performed.

## Parent's single final UI pass

Use only an explicitly authorized demo account and self-created assets. Verify two windows/tabs with distinct selections; New Album, Import/progress/errors, metadata sheets and persisted rotate/crop from menus; cross-window image/person refresh; locking closes the other viewer/Quick Look; switching/sign-out/current-account removal cancel a shared upload and reset memories; password banner/account-error presentation; preferences reflected in both sidebars/sharing; Show in All Photos affects one window; Copy in text fields versus grid/viewer; application-background Locked Folder behavior; rotated/full-screen face and stack overlays; native drag/tab/Quick Look behavior. No interactive UI claim is made by the offline tests.
