# Administration

The application menu offers Administration to a signed-in user only when `users/me.isAdmin` is true. Missing `isAdmin` grants no access. The separate window has no system-provided opening command, does not launch or restore automatically, and closes on sign-out or detected loss of administrator access. Administrator status is rechecked at most once per minute during refreshes and mutations; the server remains responsible for enforcing permissions, including API-key scopes.

Implemented:

- Server statistics including per-user usage, storage, server version and last version-check information.
- Queue counts, pause/resume, missing/all scheduling for the queue types supported by the official web client, and separate actions to clear waiting jobs or failed jobs. Jobs refresh every ten seconds while selected; an automatic failure stops network polling until Refresh succeeds; closing the window or leaving Jobs cancels polling. Feature flags gate scheduling of sidecar, OCR, face, duplicate and smart-search work. Reprocessing all and clearing queues require confirmation.
- User list including deleted users, creation, editing name/email/quota/admin/password/required password change, normal or forced deletion, and restore before removal starts. Quotas are entered in GiB and sent as bytes; blank means unlimited and is encoded as JSON null. The current administrator can edit their own user, but cannot delete themselves or reset their password through administration. Password reset means entering a new password in Edit User, with the required-change toggle.
- External libraries with owner selection, creation, name/path/exclusion editing, validation of unsaved paths for an existing library, scan, statistics and confirmed deletion. Paths refer to the server filesystem. Creating a library precedes validation because the validate endpoint requires an ID.
- Read-only complete system configuration with expandable sections and exact secret string fields concealed. All administration requests use a separate ephemeral session with no URLCache and reloadIgnoringLocalCacheData. Configuration editing was intentionally omitted to avoid overwriting unknown settings or file-managed configuration.

## API documentation and compatibility

Checked the v3.3.5 [OpenAPI specification](https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json), [API reference](https://api.immich.app), and official [jobs documentation](https://immich.app/docs/administration/jobs). The documentation site was not readable through the web fetch, so endpoint behavior was checked directly against the tagged specification and source.

Relevant paths: `/server/statistics`, `/server/storage`, `/server/version`, `/server/version-check`, `/queues`, `/queues/{name}`, `/queues/{name}/jobs`, `/jobs/{name}`, `/admin/users`, `/admin/users/{id}`, `/admin/users/{id}/restore`, `/libraries` and its ID/update/scan/validate/statistics routes, and `/system-config`.

Schemas checked: UserAdminResponse/Create/Update/DeleteDto, QueueResponse/Statistics/Update/Delete/CommandDto, QueueCommand, QueueName, LibraryResponseDto, Create/Update/ValidateLibraryDto, ValidateLibraryResponseDto, LibraryStatsResponseDto, ServerStatsResponseDto, ServerStorageResponseDto and VersionCheckStateResponseDto.

Official v3.3.5 web sources checked:

- `web/src/routes/admin/queues/QueuePanel.svelte` and `QueueCard.svelte` for supported queues, feature gates, commands and face-reset confirmation.
- `web/src/routes/admin/users/[id]/edit/+page.svelte` and `(list)/new/+page.svelte`, plus `web/src/lib/services/user-admin.service.ts` for quota/null handling, deletion, restore and password reset.
- `web/src/routes/admin/library-management/[id]/edit/+page.svelte`, library detail page, and `web/src/lib/services/library.service.ts` for editing, scanning and deletion.

`/queues` was introduced in v2.4.0 and remains alpha in v3.3.5. The jobs section is hidden on 404, rather than guessing an older response shape. Start missing/all still uses the deprecated `/jobs/{name}` command, matching the v3.3.5 web client; pause/resume and clear use the current queue endpoints. User and library PUT routes and `/system-config` remain available but are marked deprecated in v3.3.5. A section returning 404 is removed from navigation; unavailable overview endpoints are omitted individually. Missing feature flags disable corresponding queue scheduling. Unknown settings/overview fields are decoded without a fixed schema.

Apple documentation checked: SwiftUI Window, commandsRemoved, defaultLaunchBehavior, Building and customizing the menu bar with SwiftUI, NavigationSplitView, Commands, Form, DisclosureGroup, TextEditor, DismissWindowAction and Observation.Observable. These APIs are available before macOS 26; the project builds with the installed macOS 26 SDK.

## Original implementation verification

On 2026-11-04, the public demo reported v3.3.5 and `isAdmin: true`. Authenticated GETs succeeded for current user, users, queues, libraries, statistics, storage, version check and system config. Actual responses were decoded using the production Swift DTOs. Libraries returned an empty list, so a populated library response could only be checked against the specification.

An attempt to create a uniquely named temporary empty library returned HTTP 403. No object was created and no cleanup was necessary. No demo user, setting, existing library or queue was modified. Mutation flows remain unverified against a writable server. Docker was absent, so a throwaway local server was unavailable.

Build command:

```sh
xcodebuild -project ImmichGallery.xcodeproj -scheme ImmichGallery -configuration Debug -derivedDataPath build/DerivedData build
```

The Debug build succeeded with no Swift warnings. Xcode emitted its existing tooling warning that App Intents metadata extraction was skipped because the app does not link AppIntents.

Repeatable local model checks:

```sh
swiftc ImmichGallery/API/Models.swift ImmichGallery/API/Models+Admin.swift scripts/check-admin-models.swift -o /tmp/check-admin-models
/tmp/check-admin-models
```

The checks cover null quota encoding, omitted unchanged passwords, missing-admin denial, configuration decoding and unsupported manual queues. An optional directory argument also decodes saved live GET response JSON files named `immich-admin-<route-with-dashes>.json`. Live responses and credentials are not committed.

Native UI automation was attempted twice against the built application. Both calls failed with `Computer Use server error -10005: timeoutReached`, so visual layout and interactive admin flows were not verified.

## Review fixes verified on 2026-11-04

The Debug build succeeded with no warnings in changed files. The existing App Intents metadata warning remains. The app was never launched during this review fix. No live API calls, Keychain reads, or demo mutations were made. The earlier live observations above belong to the original implementation and were not repeated. Docker is still unavailable.

The v3.3.5 specification calls the `/system-config` response `AdminConfigDto`; its credential strings are `oauth.clientSecret` and `notifications.smtp.transport.password`. Only string leaves named exactly `password`, `clientSecret`, `apiKey` or `secret` are concealed. Objects such as `passwordLogin` and values such as `tokenEndpointAuthMethod` remain visible.

Jobs use the 12 queues and order from the tagged web QueuePanel. Clear Queue sends `failed: false`; Clear Failed Jobs sends the legacy `clear-failed` command. Face refresh sends `start` without `force`, distinct from missing jobs with `force: false` and resetting all with `force: true`.

Refreshes have separate state and never disable controls. Mutations wait for an in-flight refresh before executing, then reload. Repeated concurrent mutations report an error instead of silently returning. Features are fetched once per window. Polling failures stay inline, and general errors appear once in the current editor or the window instead of a modal alert.

The existing model checks now also cover exact redaction, byte formatting, finite/ranged GiB conversion and quota round trips. Run the new coordinator/command checks without launching the app or using a network:

```sh
swiftc ImmichGallery/API/Models.swift ImmichGallery/API/Models+Admin.swift ImmichGallery/API/ImmichClient+Admin.swift ImmichGallery/App/AdminModel.swift scripts/check-admin-refresh.swift -o build/admin-review/check-admin-refresh
build/admin-review/check-admin-refresh
```

This compiles the production coordinator and admin commands with stand-in session/client types. Assertions cover action execution during a blocked poll, refresh after the action, cache-free session configuration, silent offline failure, suspended polling and manual retry, reused access/feature reads, and exact clear/missing/all/refresh request bodies. It does not verify real server mutations or native UI behavior.
