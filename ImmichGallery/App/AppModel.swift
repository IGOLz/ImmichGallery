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
        guard let account = AccountStore.load() else {
            phase = .signedOut
            return
        }
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        do {
            let user = try await client.currentUser()
            start(client: client, user: user)
        } catch ImmichError.unauthorized {
            AccountStore.clear()
            phase = .signedOut
        } catch {
            // Offline or server down: open the library anyway; requests will retry as the user browses.
            start(client: client, user: nil)
        }
    }

    func signIn(client: ImmichClient, credential: Credential) async throws {
        let authed = client.with(credential: credential)
        let user = try await authed.currentUser()
        AccountStore.save(.init(serverURL: authed.serverURL, apiURL: authed.apiURL, credential: credential))
        start(client: authed, user: user)
    }

    func signOut() async {
        guard let session else { return }
        if case .accessToken = session.client.credential {
            try? await session.client.logout()
        }
        session.pipeline.removeAll()
        AccountStore.clear()
        phase = .signedOut
    }

    private func start(client: ImmichClient, user: User?) {
        let session = LibrarySession(client: client, user: user)
        session.onUnauthorized = { [weak self] in
            Task { await self?.signOut() }
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
    var exploreTags: [ExploreTag] = []
    var exploreTagsEnabled = false
    @ObservationIgnored private var exploreTagsLoaded = false
    @ObservationIgnored private var exploreTagsTask: Task<Void, Never>?

    func loadExploreTags(refresh: Bool = false) async {
        if let task = exploreTagsTask { await task.value; if !refresh { return } }
        guard refresh || !exploreTagsLoaded else { return }
        let task = Task {
            do {
                exploreTagsEnabled = try await client.explorePreferences().tags?.enabled == true
                exploreTags = exploreTagsEnabled ? try await client.exploreTags().sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending } : []
                exploreTagsLoaded = true
            } catch { handle(error) }
        }
        exploreTagsTask = task
        await task.value
        exploreTagsTask = nil
    }

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
        await reloadAlbums()
        await loadExploreTags()
    }

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

    // Explore
    func exploreRemoveFromGrids(_ ids: Set<String>) {
        for model in gridModels.values { model.exploreRemove(ids) }
    }

    func handle(_ error: Error) {
        if case ImmichError.unauthorized = error { onUnauthorized() }
    }
}
