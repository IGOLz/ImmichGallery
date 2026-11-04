import AppIntents
import Observation

@MainActor @Observable
final class MacIntegrationRouter {
    static let shared = MacIntegrationRouter()
    var pending: MacWindowRoute?
}

struct SearchPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Photos"
    static let description = IntentDescription("Search your signed-in Immich library in a new window.")
    static let openAppWhenRun = true
    @Parameter(title: "Search") var query: String

    @MainActor func perform() async throws -> some IntentResult {
        MacIntegrationRouter.shared.pending = MacWindowRoute(query: query)
        return .result()
    }
}

struct OpenAlbumIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Album"
    static let description = IntentDescription("Open an Immich album by its exact name.")
    static let openAppWhenRun = true
    @Parameter(title: "Album Name") var name: String

    @MainActor func perform() async throws -> some IntentResult {
        guard let account = AccountStore.load() else { throw MacIntentError.signIn }
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        let matches = try await client.albums().filter { $0.albumName.localizedCaseInsensitiveCompare(name) == .orderedSame }
        guard matches.count == 1, let album = matches.first else { throw MacIntentError.albumName }
        MacIntegrationRouter.shared.pending = MacWindowRoute(albumID: album.id)
        return .result()
    }
}

private enum MacIntentError: LocalizedError {
    case signIn, albumName
    var errorDescription: String? {
        switch self {
        case .signIn: String(localized: "Sign in to Immich Gallery first.")
        case .albumName: String(localized: "Choose a unique, existing album name.")
        }
    }
}

struct ImmichGalleryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SearchPhotosIntent(), phrases: ["Search photos in \(.applicationName)"], shortTitle: "Search Photos", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenAlbumIntent(), phrases: ["Open album in \(.applicationName)"], shortTitle: "Open Album", systemImageName: "rectangle.stack")
    }
}
