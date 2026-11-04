# Administration

The application menu offers Administration to a signed-in user only when `users/me.isAdmin` is true. Missing `isAdmin` grants no access. The separate window has no system-provided opening command, does not launch or restore automatically, and closes on sign-out or detected loss of administrator access. Each refresh and mutation rechecks `users/me`; the server remains responsible for enforcing permissions, including API-key scopes.

Implemented:

- Server statistics including per-user usage, storage, server version and last version-check information.
- Queue counts, pause/resume, missing/all scheduling for the queue types supported by the official web client, and clearing waiting/failed jobs. Jobs refresh every ten seconds while selected; closing the window or leaving Jobs cancels polling. Feature flags gate scheduling of sidecar, OCR, face, duplicate and smart-search work. Reprocessing all and clearing queues require confirmation.
- User list including deleted users, creation, editing name/email/quota/admin/password/required password change, normal or forced deletion, and restore before removal starts. Quotas use bytes, blank means unlimited and is encoded as JSON null. Self-management is disabled to avoid deleting or demoting the active administrator. Password reset means entering a new password in Edit User, with the required-change toggle.
- External libraries with owner selection, creation, name/path/exclusion editing, validation of unsaved paths for an existing library, scan, statistics and confirmed deletion. Paths refer to the server filesystem. Creating a library precedes validation because the validate endpoint requires an ID.
- Read-only complete system configuration with expandable sections and sensitive fields concealed. Configuration editing was intentionally omitted to avoid overwriting unknown settings or file-managed configuration.

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

## Verification

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
