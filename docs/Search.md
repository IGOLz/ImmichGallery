# Advanced search

Search is available in the sidebar and through the toolbar search field. Submit text with Return. The results view offers Context, File Name, Description, and Text in Images modes. Context is shown only when smart search is enabled; OCR requires the server's `ocr` feature flag. Empty text with active filters uses metadata search.

Filters combine people, country/state/city, camera make/model/lens, inclusive local calendar dates, photo/video type, archived assets, favorites, assets outside albums, and an exact one-to-five-star rating. Rating controls appear only when `users/me/preferences.ratings.enabled` is true. People are paged and show face thumbnails. Suggestion menus use the server's distinct metadata values; typing filters those values and also permits manually entered values. Changing a parent location or camera clears its dependent fields.

Chips above results reopen the editable filter sheet. Recent searches preserve the complete query and filters, keep at most 20 entries, and can be cleared. They are stored in UserDefaults under a server API URL and user ID key, without tokens. No history is persisted if the user ID is unavailable. Toolbar completions offer the text of recent searches; the Recent Searches menu restores their complete filters. Explore cities are offered in the empty search view.

Results reuse AssetGridContainer, including infinite paging, selection, context menus, the viewer, export, and inspector. Later-page failures now surface through the grid's existing error alert and remain retryable. Empty pages no longer create an empty results section that hides the No Results state.

## Contracts checked

- Immich v3.3.5 `open-api/immich-openapi-specs.json`: POST `/search/smart`, POST `/search/metadata`, GET `/search/suggestions`, GET `/search/explore`, GET `/people`, GET `/server/features`, GET `/users/me/preferences`; SmartSearchDto, MetadataSearchDto, SearchSuggestionType, SearchExploreResponseDto, SearchExploreItem, RatingsResponse, and search paging fields.
- Official v3.3.5 web source: `web/src/lib/managers/search-manager.svelte.ts`, `SearchTextSection.svelte`, `SearchLocationSection.svelte`, `SearchDisplaySection.svelte`, and `search-bar-utils.ts`. OCR maps to metadata `ocr`, archive maps to `visibility: archive`, and date limits cover complete days.
- https://docs.immich.app/features/searching/ for supported modes and filters. https://api.immich.app was fetched, but its client-rendered endpoint pages were not readable through the documentation fetcher; the version-pinned OpenAPI and official web source supply the exact contract.
- Apple's SwiftUI reference for searchSuggestions, DatePicker, and sheet. These predate macOS 26. The other UI primitives follow the existing app's SwiftUI patterns.

## Compatibility

v3.3.5 marks flat search filters deprecated in favor of SearchFilter, but accepts them and uses them in its own web client. Using the flat form retains v2 compatibility. Smart search uses numbered pages; metadata accepts either numbered pages or the returned cursor. A missing smart endpoint falls back to filename metadata search. Missing OCR flags hide OCR; missing ratings preferences hide ratings. Suggestion 404s hide the suggestion menu while allowing typed filters; unavailable explore data is omitted. A v2 server was not available for runtime checks.

Exact ratings 1–5 are supported. An explicit unrated filter and null metadata values are not exposed. Explore dates are omitted because the endpoint returns month buckets rather than Things categories. Only city explore groups are exposed.

## Verification

The requested Debug xcodebuild command succeeded. No Swift compiler warnings were introduced. Xcode emitted its existing AppIntents metadata-extraction warning because the app has no AppIntents dependency.

Read-only requests to https://demo.immich.app succeeded for every suggestion type, explore, preferences, feature flags, people, filename, description, OCR, metadata paging, smart paging, and combined smart/metadata filters including camera, type, dates, favorite, not-in-album, and rating. Real responses were decoded using the app's actual Swift DTOs. No shared demo content was modified.

`scripts/check-search.swift` checks field mapping for each mode, preservation of combined filters, deterministic people IDs, date validation, and history serialization. Its optional fixture-folder argument decodes live responses with the production DTOs. Compile/run instructions are in its header. Response fixtures and authentication data remain outside the repository.

App launch was attempted. macOS resolved the existing signed-in app instance, whose sidebar did not contain this build's Search entry. Authenticated UI behavior in this build was therefore not verified; no actions were taken in the existing instance.
