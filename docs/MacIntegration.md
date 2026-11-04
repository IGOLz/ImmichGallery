# Native macOS integrations

Implemented for macOS 26 with no added dependencies or targets.

- Grid multi-selection and viewer drag export use SwiftUI Transferable file representations. Originals download only when the destination requests files. Images and movies advertise their respective content types. Each transfer gets a private temporary directory, preserves the original filename, and strips server-supplied path components. Transfers older than 24 hours expire on a later transfer.
- Space in the grid downloads selected originals and opens QLPreviewPanel. The controller participates in the AppKit responder chain, supports multiple files, reports errors through the existing grid alert, and deletes preview files when control ends. Return and double-click retain the in-app viewer.
- A typed WindowGroup and explicit Command-N New Window command create independent LibrarySession/grid/selection/navigation state. Album context menus in the sidebar and album collection open windows or AppKit tabs. Credentials remain shared through the existing app model. Each window refreshes its own library state; mutations do not immediately invalidate grids in other windows.
- Search Photos and Open Album App Intents are exposed through AppShortcutsProvider. Search uses the existing smart-search/filename fallback. Open Album matches an exact case-insensitive name, rejects missing or ambiguous matches, and uses the existing Keychain account. Intents open separate windows and never put credentials in a route. Search invoked while signed out remains pending until sign-in.
- SystemNotifier.requestPermission() and SystemNotifier.completed(title:body:) provide a reusable notification API. Settings has an opt-in completion-notification switch. The existing original exporter sends completion counts while the app is inactive and avoids bringing Finder forward during background completion. Denied permission or disabled notifications are silent.
- Localizable.xcstrings covers existing app UI and new integrations in Italian. AppShortcuts.xcstrings translates invocation phrases. InfoPlist.xcstrings translates the local-network usage explanation. The only project-file change adds `it` to knownRegions.

## Sources checked

Fetched the v3.3.5 OpenAPI spec once from https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json . Checked GET /assets/{id}, GET /assets/{id}/original, GET /albums, POST /search/metadata, POST /search/smart, their referenced AssetResponseDto/AlbumResponseDto/SearchResponseDto schemas, authentication and permissions. These endpoints are stable in v2 and v3; no new server-specific endpoint or DTO is required. Download failures, including missing originals and permission errors, propagate instead of creating an error-body file. Existing search uses server/features to choose smart search versus metadata search.

Cross-checked https://api.immich.app/endpoints/assets/downloadAsset and https://immich.app/docs . Read tagged official web/src/lib/utils/asset-utils.ts for download and filename handling. No upload/sync behavior was added, so mobile upload code was not needed.

Read Apple's documentation for FileRepresentation, dragContainer(for:in:_:), QLPreviewPanel including responder-chain ownership, WindowGroup, AppShortcutsProvider, and UNUserNotificationCenter. Checked API signatures against the installed macOS SDK and built for the project's macOS 26 deployment target. dragContainer supports macOS 26.

## Verification

The required Debug xcodebuild command succeeded with zero warnings. Build log is local and ignored at build/MacIntegration/build.log.

scripts/verify-mac-integration.swift compiles with the real API client/DTOs and checks the public demo. Verified server 3.3.5, decoded 236 albums, metadata search, asset details, smart search, and downloaded a 1,779,462-byte original. Removed the temporary original and logged out the test session. No server library data or settings were changed.

python3 scripts/check-mac-localization.py checks the compiler's stringsdata against the Italian catalogs and verifies format/shortcut placeholders. Passed for all 123 extracted strings. The catalog also includes the dynamically selected Email & Password method label, which the compiler does not extract automatically.

Launched this checkout's built app with Italian language arguments and confirmed its process. Native UI inspection failed with `Computer Use server error -10005: timeoutReached`. Other feature agents had their own app instances running; no other instance was stopped or used. End-to-end Finder drop, Quick Look rendering, tab attachment, Shortcuts execution and notification delivery remain manual verification items. Ad-hoc signing/Keychain permission and system notification authorization can affect those checks.

## Deliberate omissions

No widget extension: robust delivery needs a separate extension target, App Group, credential-sharing design and suitable signing. A menu bar extra is optional and adds little without background sync. Neither was added. Shortcuts includes Search Photos and Open Album; unattended export is omitted because selecting a sandbox-authorized destination needs a separate output contract.

## Shared-file changes

- App/ImmichGalleryApp.swift: replace the single Window with a typed WindowGroup, install MacWindowRoot and MacIntegrationCommands.
- Views/MainView.swift: initializer for album/search routes; add album sidebar context-menu actions.
- Views/Grid/AssetGridView.swift: multi-item drag container, draggable cells, separate Space Quick Look from Return viewer handling.
- Views/Viewer/AssetViewer.swift: add the current original as a drag source.
- Views/Albums/AlbumsView.swift: add album context-menu actions.
- Views/Settings/SettingsView.swift: insert MacNotificationPreference.
- Support/Exporter.swift: call SystemNotifier on completion and reveal exported files only while foregrounded.
- ImmichGallery.xcodeproj/project.pbxproj: add Italian knownRegions entry only.

No changes to README.md, shared API/DTO files, AppModel.swift or AssetGridModel.swift.
