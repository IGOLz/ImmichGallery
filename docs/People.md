# People and faces

People opens a detail page with a face thumbnail, name, birthday and current age,
asset count, and the existing month timeline. Person Actions edits the name and
birthday, clears a birthday, toggles favorite/hidden, and merges another person
into the current person after confirmation. Show Hidden People includes hidden
records. Favorite and hidden badges identify their state. The inspector opens the
same detail page in a sheet, including unnamed people.

The photo viewer toolbar offers Show Faces and Manage Faces. Boxes use each
face's image dimensions and the displayed image's aspect-fit rectangle. Their
positions track zoom/pan, while strokes and labels stay at screen size. Boxes
pass pointer events through to the viewer; Manage Faces holds the actions.
Show Faces persists across photos. Boxes are hidden when isEdited is true or
unknown, because the viewer currently requests unedited previews and originals.
A TODO at the coordinate check explains when to enable edited boxes.
Each list row can assign the face to an existing or newly created named person,
set the associated person's featured photo, or remove an assigned face after confirmation. Null person values display as
Unassigned Face. Removal sends force=false, preserving the server's protection
against unsafe removal; errors are displayed rather than automatically forcing
an operation. These controls require the facialRecognition server feature.

People and pickers request 100 records per page, deduplicate IDs, load thumbnails
lazily through ImagePipeline, and reject stale responses when filters change.
The v3.3.5 response includes hasNextPage; total plus nonempty pages are a fallback
for older responses. Pickers search on
the server and offer explicit Load More. Failed creation-plus-assignment retains
the created person in the picker for retry rather than creating a duplicate.

## Contracts checked

- Immich v3.3.5 OpenAPI, fetched once from
  https://raw.githubusercontent.com/immich-app/immich/v3.3.5/open-api/immich-openapi-specs.json
- GET/POST/PUT /people; GET/PUT /people/{id}; GET /people/{id}/statistics;
  POST /people/merge and legacy POST /people/{id}/merge; GET /faces?id=; PUT/DELETE /faces/{id}.
- PersonResponseDto, PersonCreateDto, PersonUpdateDto, PeopleUpdateDto,
  PeopleResponseDto, PersonStatisticsResponseDto, MergePersonDto,
  AssetFaceResponseDto, FaceDto, AssetFaceDeleteDto, BulkIdResponseDto.
- PUT /people bulk takes people update items and returns per-record results.
  This UI edits one person at a time using PUT /people/{id} instead.
- PUT /faces/{id} uses the destination PERSON ID in the path and the FACE ID
  in the body. Birthday clearing requires an explicit JSON null.
- https://api.immich.app/endpoints/people and
  https://docs.immich.app/features/facial-recognition/
- Official v3.3.5 web source: asset-viewer/face-editor/FaceEditor.svelte,
  stores/face.svelte.ts, faces-page/AssignFaceSidePanel.svelte,
  services/person.service.ts, and the person route's MergeFaceSelector.svelte
  and UnmergeFaceSelector.svelte. Reviewed aspect-fit offsets, unassigned faces,
  person action visibility, new-person assignment, and merge direction.
- Apple GeometryReader, DatePicker, sheet(item:), and confirmationDialog docs.
  GeometryReader is available since macOS 10.15; the SwiftUI controls used here
  are available before the project's macOS 26 deployment target. The Xcode 26
  SDK build checks availability and signatures.

The selected endpoints and favorite/birthday fields are v2-stable according to
OpenAPI history. Missing optional birthday/favorite fields decode safely. Face
controls disappear when GET /faces returns 404. Merge uses POST /people/merge
with the target ID first, falling back to the legacy endpoint only on HTTP 404.
Single-person updates retain PUT /people/{id}, which is deprecated but still
supported in v3.3.5; bulk updates require per-record result handling. Server permission failures remain visible to users.
No new sharing or administration permissions are assumed.

## Verification

Debug xcodebuild succeeded. There were no Swift compiler warnings; Xcode emitted
its existing AppIntents metadata warning because the app does not use AppIntents.

On demo.immich.app, confirmed server version 3.3.5 and read real people, person
statistics, person timeline buckets, bucket assets, and two asset faces. Decoded
real people/person/statistics/faces responses using the production Swift DTOs.
Created two disposable people, verified rename, birthday set and explicit-null
clear, hide/unhide, favorite/unfavorite, and merge. Deleted all disposable people.
No existing people or assets were modified.

Attempted upload of a generated 64x64 PNG to prepare disposable face mutation
fixtures. The demo rejected upload with HTTP 403, before creating any asset or
person. Face assignment, featured-photo writes, and face removal therefore have
schema/source verification but no live mutation verification. No existing shared
faces were changed to work around this restriction.

Run the repeatable local checks from the repository root:

```sh
mkdir -p build/people-verification
xcrun swiftc ImmichGallery/API/Models.swift ImmichGallery/API/Models+People.swift scripts/checks/people.swift -o build/people-verification/checks
build/people-verification/checks
```

The checks cover letterboxed box positioning, invalid image sizes, unassigned
face decoding, birthday clear encoding, and omission of unchanged birthday fields.
An optional argument supplies a directory of live JSON fixtures for DTO checks;
live responses and build logs are kept under ignored build/ only.

## Review fixes verification

The review-fix build succeeded without Swift compiler warnings. The existing
AppIntents metadata warning remains. The built app was never launched during
these fixes, and no live Immich requests or mutations were made.

Inspector people refreshes retain the current details, albums and sheet host,
including when the refreshed asset has no people. Person headers disappear while
their viewer is open. Person edits and face mutations invalidate cached grids.
The People grid has Rename, Hide/Unhide, Merge and Favorite actions, and Show
Hidden People has an icon.

Featured-photo updates invalidate both thumbnail caches, then retry fresh bytes
after 1, 3 and 6 seconds until the bytes differ. If server generation takes longer,
the bounded retries may still show the old thumbnail until a later refresh.

Offline checks cover 8x zoom with pan, birthday encoding, thumbnail memory-cache
reuse and invalidation, delayed generated thumbnails, ordered bulk merge and
HTTP-404 legacy fallback. No network traffic leaves the mocked test process:

```sh
xcrun swiftc -swift-version 6 ImmichGallery/API/*.swift ImmichGallery/Support/ImagePipeline.swift scripts/checks/people-network.swift -o build/people-verification/network-checks
build/people-verification/network-checks
```

Sheet continuity, pointer gestures and header layout have source/build checks only;
interactive verification remains for an authorized app session.
