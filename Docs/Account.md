# Account implementation

Account settings are split into General, Account, Security, Preferences, and Accounts tabs. The library toolbar includes an account switcher and notifications bell.

Implemented:
- Profile name editing, email display, usage/quota display, authenticated profile image loading, JPEG upload from a security scoped file importer, and image removal.
- Password changes with confirmation entry, eight-character validation, and optional invalidation of other sessions. Hidden when password login is disabled.
- API key listing, permission selection/filtering, creation with a one-time secret and copy action, rename, and confirmed deletion. Permission names come from the v3.3.5 Permission schema.
- Device/session listing with current marker, device OS/type/app version and last activity, confirmed individual revocation and logout of other sessions. Bulk revocation requires session-token authentication.
- Notifications list, unread count, mark read/all read and delete. Polling runs once per minute only while the scene is active, backs off on failure, stops on cancellation and hides the bell on 403/404.
- Server preferences for memories, ratings, folders, tags, people, shared links, web sidebar visibility, memory duration, people threshold/update strategy, default album order, download size and embedded video inclusion, email toggles, Cast, recently added web sidebar and support badge. Only available groups/fields appear. Loaded values are exposed as LibrarySession.preferences.
- Multiple accounts in Keychain, account menu and Settings switcher, adding through the existing login UI, local removal, last selected restoration, and legacy credential migration. Migration now copies the legacy item without changing/deleting it. Explicit Sign Out retains the existing behavior of deleting legacy credentials.
- New LibrarySession and memory cache per switch, SHA-256-named disk cache directories per API URL/user ID. Old session unauthorized callbacks cannot sign out a newly selected account.

No project file or README changes. No dependencies.

## Sources and contracts

Fetched the v3.3.5 OpenAPI document once:
https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json

Checked Users, Authentication, API keys, Sessions and Notifications operations:
- GET/PUT /users/me; GET/PUT /users/me/preferences
- POST/DELETE /users/profile-image; GET /users/{id}/profile-image
- POST /auth/change-password: password, newPassword, invalidateSessions. The requested PUT is not the actual endpoint.
- GET/POST /api-keys, PUT/DELETE /api-keys/{id}
- GET/DELETE /sessions, DELETE /sessions/{id}
- GET/PUT /notifications, DELETE /notifications/{id}

Checked request/response schemas, Permission, PersonUpdateStrategy, all preference groups, multipart file field, notification readAt semantics, session.current and nullable appVersion. User and preference updates and API key rename use PUT endpoints still supported but marked deprecated in v3.3.5. Optional response fields/groups tolerate v2.x; missing preferences/keys/sessions endpoints hide their controls, missing notification endpoints hide the bell. v2.x was not live tested.

Cross-checked https://api.immich.app and https://docs.immich.app/features/user-settings/ and the API key permissions section at https://docs.immich.app/features/command-line-interface/.

Read official source at tag v3.3.5:
web/src/routes/(user)/user-settings/{UserProfileSettings,ChangePasswordSettings,DeviceList,DownloadSettings,FeatureSettings,NotificationsSettings,UserApiKeyList}.svelte
web/src/lib/components/user-settings-page/UserApiKeyGrid.svelte
web/src/lib/stores/notification-manager.svelte.ts

Apple references checked: SwiftUI TabView and fileImporter, Security Keychain services, AppKit NSPasteboard, Foundation URLCache. All compile against the macOS 26 SDK and app deployment target. Existing Form, Observation, Task and Settings scene patterns are reused.

## Verification

Build:
xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build

Build succeeded. Only the standard AppIntents metadata extraction warning appears; no source warnings.

Demo checks:
python3 Tests/AccountLiveCheck.py

This script is hardcoded to https://demo.immich.app/api/ and its public demo credentials. It reads version/user/preferences/keys/sessions/notifications, creates and renames a temporary asset.read key, deletes that key in finally, and deletes only its own login session. It saves public response fixtures under gitignored build/AccountChecks, with the created key secret redacted. It never reads Keychain. It never modifies profile/password/preferences or other sessions/notifications.

Actual demo result: v3.3.5; all six reads succeeded; temporary key creation/rename/deletion succeeded; only this script's login session was deleted. Notifications list was empty, so optional notification fields also have a synthetic schema check.

DTO/request checks:
swiftc -swift-version 6 ImmichGallery/API/Models.swift ImmichGallery/API/ImmichClient.swift ImmichGallery/API/Models+Account.swift ImmichGallery/API/ImmichClient+Account.swift Tests/AccountChecks.swift -o build/AccountChecks/check
build/AccountChecks/check

Passed: decoding real responses; optional old-server groups; preferences encode/decode; password method/path/body; notification timestamp/IDs; multipart file body/auth; independent caches. URLProtocol intercepts all request-contract checks. No real network, Keychain or account-store writes occur in this check.

UI limit and incident:
Before the user's urgent stop instruction, one built app was launched. It automatically restored the user's real account at immich.igol.dev and made read-only library/account GET requests. General Settings and the library toolbar were observed. No server mutation control was invoked and no write request was intentionally sent to that server. The then-current restore migration also saved the multi-account Keychain item and removed the legacy Keychain item. This local migration had already occurred before the stop instruction. The app was immediately quit using Command-Q after the instruction; the UI tool reported “App quit”. No further UI runs or Keychain accesses were made. Migration was subsequently changed to preserve the legacy item on future restores. Three settings tabs initially had duplicate SwiftUI IDs; those IDs are now distinct, verified by compilation only. Final merged-app UI verification belongs to the parent.

Untested by design: profile/name/password/preference mutations on the shared demo, deleting anyone else's sessions/notifications, end-to-end account switching and Keychain migration test runs, and final tab layout after the identity correction. A real account's Keychain was not read through scripts or diagnostic tooling; automatic restoration happened only through the launched app before the stop instruction.
