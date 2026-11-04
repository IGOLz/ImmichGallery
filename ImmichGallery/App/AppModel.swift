import Foundation
import Observation

/// Top-level app state: signed out, or signed in with a `LibrarySession`.
@MainActor @Observable
final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case signedIn(LibrarySession)
    }

    private(set) var phase: Phase = .launching

    var session: LibrarySession? {
        if case .signedIn(let session) = phase { session } else { nil }
    }

    func restore() async {
        guard case .launching = phase else { return }
        guard let account = AccountVault.selected?.account ?? AccountVault.legacyAccountForMigration else {
            phase = .signedOut
            return
        }
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        do {
            let user = try await client.currentUser()
            try AccountVault.save(account: account, user: user)
            start(client: client, user: user)
        } catch ImmichError.unauthorized {
            if let selected = AccountVault.selected { try? AccountVault.remove(selected.id) }
            UserDefaults.standard.set(true, forKey: "accountVaultMigrated")
            phase = .signedOut
        } catch {
            // Offline or server down: open the library anyway; requests will retry as the user browses.
            start(client: client, user: nil)
        }
    }

    func signIn(client: ImmichClient, credential: Credential) async throws {
        let authed = client.with(credential: credential)
        let user = try await authed.currentUser()
        try AccountVault.save(account: .init(serverURL: authed.serverURL, apiURL: authed.apiURL, credential: credential), user: user)
        start(client: authed, user: user)
    }

    func signOut() async {
        guard let session else { return }
        if case .accessToken = session.client.credential {
            try? await session.client.logout()
        }
        guard self.session === session else { return }
        session.pipeline.removeAll()
        if let selected = AccountVault.selected { try? AccountVault.remove(selected.id) }
        AccountStore.clear()
        phase = .signedOut
    }

    func switchAccount(_ entry: AccountVault.Entry) async throws {
        let account = entry.account
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        let user = try await client.currentUser()
        try AccountVault.select(entry.id)
        start(client: client, user: user)
    }

    func removeAccount(_ entry: AccountVault.Entry) throws {
        try AccountVault.remove(entry.id)
        if session?.client.apiURL == entry.account.apiURL, session?.user?.id == entry.userID {
            session?.pipeline.removeAll()
            phase = .signedOut
        }
    }

    private func start(client: ImmichClient, user: User?) {
        // Old view tasks can finish, but their session and memory cache are never reused.
        let isolated = client.accountIsolated(userID: user?.id ?? AccountVault.selected?.userID ?? UUID().uuidString)
        let session = LibrarySession(client: isolated, user: user)
        session.onUnauthorized = { [weak self, weak session] in
            Task {
                guard let self, self.session === session else { return }
                await self.signOut()
            }
        }
        phase = .signedIn(session)
        Task { await session.bootstrap() }
    }
}

/// Everything that belongs to one signed-in server/user.
@MainActor @Observable
final class LibrarySession {
    let client: ImmichClient
    let pipeline: ImagePipeline
    private(set) var user: User?
    private(set) var features = ServerFeatures()
    private(set) var version: ServerVersion?
    private(set) var albums: [Album] = []
    var preferences: AccountPreferences? // Account: loaded preferences for feature consumers.

    @ObservationIgnored var onUnauthorized: () -> Void = {}
    @ObservationIgnored private var gridModels: [GridSource: AssetGridModel] = [:]

    init(client: ImmichClient, user: User?) {
        self.client = client
        self.pipeline = ImagePipeline(client: client)
        self.user = user
    }

    func bootstrap() async {
        async let features = try? client.serverFeatures()
        async let version = try? client.serverVersion()
        async let user = try? client.currentUser()
        self.features = await features ?? ServerFeatures()
        self.version = await version
        if let user = await user { self.user = user }
        preferences = try? await client.accountPreferences()
        await reloadAlbums()
    }

    func refreshAccountUser() async throws { user = try await client.currentUser() }

    func reloadAlbums() async {
        do {
            albums = try await client.albums().sorted {
                ($0.lastModifiedAssetTimestamp ?? "") > ($1.lastModifiedAssetTimestamp ?? "")
            }
        } catch { handle(error) }
    }

    /// Grid models are cached per source so switching sidebar items keeps loaded data.
    func gridModel(for source: GridSource) -> AssetGridModel {
        if let model = gridModels[source] { return model }
        let model = AssetGridModel(source: source, session: self)
        gridModels[source] = model
        return model
    }

    /// Mutations in one view (favorite, delete…) can affect other cached grids.
    func invalidateGrids(except keep: AssetGridModel? = nil) {
        for model in gridModels.values where model !== keep { model.markStale() }
    }

    func handle(_ error: Error) {
        if case ImmichError.unauthorized = error { onUnauthorized() }
    }
}
