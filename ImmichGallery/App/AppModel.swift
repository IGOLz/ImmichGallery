import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case signedIn(LibrarySession)
    }
    private(set) var phase: Phase = .launching
    private(set) var entries: [AccountVault.Entry] = []
    private(set) var switching = false
    private(set) var currentAccountID: String?
    var accountError: String?

    var session: LibrarySession? {
        if case .signedIn(let session) = phase { session } else { nil }
    }

    private func refreshEntries() throws { entries = try AccountVault.loadEntries() }

    func restore() async {
        guard case .launching = phase else { return }
        do {
            try refreshEntries()
            let selected = try AccountVault.selectedEntry()
            guard let account = selected?.account ?? AccountVault.legacyAccountForMigration else {
                phase = .signedOut
                return
            }
            currentAccountID = selected?.id
            let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
            let user: User?
            do { user = try await client.currentUser() }
            catch ImmichError.unauthorized {
                if let selected {
                    try AccountVault.remove(selected.id)
                    try removeSavedCache(selected)
                }
                try refreshEntries()
                UserDefaults.standard.set(true, forKey: "accountVaultMigrated")
                phase = .signedOut
                return
            } catch { user = nil }
            if let user {
                try AccountVault.save(account: account, user: user)
                try refreshEntries()
                currentAccountID = account.apiURL.absoluteString + "|" + user.id
            }
            // Credential identity is stable even before a legacy user's ID is available.
            let fallback = try JSONEncoder().encode(account.credential).base64EncodedString()
            start(client: client, user: user, cacheUserID: user?.id ?? selected?.userID ?? "offline-" + fallback)
        } catch {
            accountError = error.localizedDescription
            phase = .signedOut
        }
    }

    func signIn(client: ImmichClient, credential: Credential) async throws {
        guard !switching else { return }
        switching = true
        defer { switching = false }
        let authed = client.with(credential: credential)
        let user = try await authed.currentUser()
        try AccountVault.save(account: .init(serverURL: authed.serverURL, apiURL: authed.apiURL, credential: credential), user: user)
        try refreshEntries()
        currentAccountID = authed.apiURL.absoluteString + "|" + user.id
        start(client: authed, user: user, cacheUserID: user.id)
    }

    func signOut() async {
        guard !switching, let session else { return }
        switching = true
        defer { switching = false }
        do {
            // Persist removal first: a vault failure must leave the live login intact.
            if let currentAccountID { try AccountVault.remove(currentAccountID) }
            else { _ = try AccountVault.loadEntries() }
            UserDefaults.standard.set(true, forKey: "accountVaultMigrated")
            try refreshEntries()
        } catch { accountError = error.localizedDescription; return }
        if case .accessToken = session.client.credential { try? await session.client.logout() }
        guard self.session === session else { return }
        session.upload.cancelAll() // Upload
        session.pipeline.removeAll()
        phase = .signedOut
        currentAccountID = nil
        do { try clearCache(session) } catch { accountError = error.localizedDescription }
    }

    func switchAccount(_ entry: AccountVault.Entry) async throws {
        guard !switching, currentAccountID != entry.id else { return }
        switching = true
        defer { switching = false }
        let previous = session
        let account = entry.account
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        let user = try await client.currentUser()
        guard session === previous else { return }
        try AccountVault.select(entry.id)
        try refreshEntries()
        currentAccountID = entry.id
        start(client: client, user: user, cacheUserID: user.id)
    }

    func removeAccount(_ entry: AccountVault.Entry) throws {
        guard !switching else { return }
        try AccountVault.remove(entry.id)
        try refreshEntries()
        if currentAccountID == entry.id {
            let old = session
            old?.pipeline.removeAll()
            phase = .signedOut
            currentAccountID = nil
            if let old { try clearCache(old) }
        }
        try removeSavedCache(entry)
    }

    private func removeSavedCache(_ entry: AccountVault.Entry) throws {
        try ImmichClient.removeAccountCache(apiURL: entry.account.apiURL, userID: entry.userID)
        let fallback = try JSONEncoder().encode(entry.account.credential).base64EncodedString()
        try ImmichClient.removeAccountCache(apiURL: entry.account.apiURL, userID: "offline-" + fallback)
    }

    private func clearCache(_ session: LibrarySession) throws {
        if let credential = session.client.credential {
            let fallback = try JSONEncoder().encode(credential).base64EncodedString()
            try ImmichClient.removeAccountCache(apiURL: session.client.apiURL, userID: "offline-" + fallback)
        }
        try ImmichClient.removeAccountCache(apiURL: session.client.apiURL, userID: session.cacheUserID)
        if let id = session.user?.id, id != session.cacheUserID {
            try ImmichClient.removeAccountCache(apiURL: session.client.apiURL, userID: id)
        }
    }

    private func start(client: ImmichClient, user: User?, cacheUserID: String) {
        let isolated = client.accountIsolated(userID: cacheUserID)
        let session = LibrarySession(client: isolated, user: user, cacheUserID: cacheUserID)
        let legacyCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageCache", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: legacyCache.path) { try FileManager.default.removeItem(at: legacyCache) }
        } catch { accountError = error.localizedDescription }
        session.onUnauthorized = { [weak self, weak session] in
            Task {
                guard let self, self.session === session else { return }
                await self.signOut()
            }
        }
        session.onUserLoaded = { [weak self, weak session] user in
            guard let self, self.session === session, !self.switching, let credential = client.credential else { return }
            do {
                try AccountVault.save(account: .init(serverURL: client.serverURL, apiURL: client.apiURL, credential: credential), user: user)
                try self.refreshEntries()
                self.currentAccountID = client.apiURL.absoluteString + "|" + user.id
            } catch { self.accountError = error.localizedDescription }
        }
        self.session?.upload.cancelAll() // Upload: the previous account's queue goes away with its session.
        phase = .signedIn(session)
        Task { await session.bootstrap() }
    }
}

/// Everything that belongs to one signed-in server/user.
@MainActor @Observable
final class LibrarySession {
    let client: ImmichClient
    let albumActions = AlbumsActions() // Albums
    let sharing: SharingModel // Sharing
    let upload: UploadQueue // Upload
    let pipeline: ImagePipeline
    private(set) var user: User?
    private(set) var features = ServerFeatures()
    private(set) var version: ServerVersion?
    private(set) var albums: [Album] = []
    private(set) var preferences: AccountPreferences? // Account: loaded preferences for feature consumers.

    let cacheUserID: String
    @ObservationIgnored var onUserLoaded: (User) -> Void = { _ in }
    @ObservationIgnored var onUnauthorized: () -> Void = {}
    @ObservationIgnored private var gridModels: [GridSource: AssetGridModel] = [:]

    init(client: ImmichClient, user: User?, cacheUserID: String) {
        self.cacheUserID = cacheUserID
        self.client = client
        self.sharing = SharingModel(client: client)
        self.pipeline = ImagePipeline(client: client)
        self.upload = UploadQueue(client: client)
        self.upload.onFinished = { [weak self] in // Upload
            self?.invalidateGrids()
            Task { await self?.reloadAlbums() }
        }
        self.upload.onError = { [weak self] in self?.handle($0) } // Upload
        self.user = user
    }

    func bootstrap() async {
        async let features = try? client.serverFeatures()
        async let version = try? client.serverVersion()
        async let user = try? client.currentUser()
        self.features = await features ?? ServerFeatures()
        self.version = await version
        if let user = await user { self.user = user; onUserLoaded(user) }
        preferences = try? await client.accountPreferences()
        await reloadAlbums()
        await sharing.reload() // Sharing
    }

    func setPreferences(_ value: AccountPreferences) { preferences = value }

    func refreshAccountUser() async throws { user = try await client.currentUser() }

    func reloadAlbums() async {
        do {
            albums = try await client.albumCollections(legacy: (version?.major ?? 3) < 3).sorted { // Albums
                ($0.lastModifiedAssetTimestamp ?? "") > ($1.lastModifiedAssetTimestamp ?? "")
            }
        } catch { handle(error) }
    }

    /// Grid models are cached per source so switching sidebar items keeps loaded data.
    func gridModel(for source: GridSource) -> AssetGridModel {
        if let model = gridModels[source] { return model }
        // Only retain the current search, including its loaded pages.
        switch source {
        case .search, .filteredSearch:
            gridModels = gridModels.filter { key, _ in
                switch key { case .search, .filteredSearch: false; default: true }
            }
        default: break
        }
        let model = AssetGridModel(source: source, session: self)
        gridModels[source] = model
        return model
    }

    func invalidateAlbumGrid(_ id: String) {
        gridModels[.album(id)]?.markStale()
    }

    func discardAlbumGrid(_ id: String) {
        gridModels.removeValue(forKey: .album(id))
        albumActions.details.removeValue(forKey: id)
    }

    /// Mutations in one view (favorite, delete…) can affect other cached grids.
    func invalidateGrids(except keep: AssetGridModel? = nil) {
        for model in gridModels.values where model !== keep { model.markStale() }
    }

    func handle(_ error: Error) {
        if case ImmichError.unauthorized = error { onUnauthorized() }
    }
}
