import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case signedIn(AccountServices)
    }
    private(set) var phase: Phase = .launching
    private(set) var entries: [AccountVault.Entry] = []
    private(set) var switching = false
    private(set) var currentAccountID: String?
    var accountError: String?

    var services: AccountServices? {
        if case .signedIn(let services) = phase { services } else { nil }
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
        guard !switching, let services else { return }
        switching = true
        defer { switching = false }
        do {
            // Persist removal first: a vault failure must leave the live login intact.
            if let currentAccountID { try AccountVault.remove(currentAccountID) }
            else { _ = try AccountVault.loadEntries() }
            UserDefaults.standard.set(true, forKey: "accountVaultMigrated")
            try refreshEntries()
        } catch { accountError = error.localizedDescription; return }
        if case .accessToken = services.client.credential { try? await services.client.logout() }
        guard self.services === services else { return }
        services.upload.cancelAll() // Upload
        services.pipeline.removeAll()
        MacIntegrationRouter.shared.pending.removeAll()
        phase = .signedOut
        currentAccountID = nil
        do { try clearCache(services) } catch { accountError = error.localizedDescription }
    }

    func switchAccount(_ entry: AccountVault.Entry) async throws {
        guard !switching, currentAccountID != entry.id else { return }
        switching = true
        defer { switching = false }
        let previous = services
        let account = entry.account
        let client = ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential)
        let user = try await client.currentUser()
        guard services === previous else { return }
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
            let old = services
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

    private func clearCache(_ services: AccountServices) throws {
        if let credential = services.client.credential {
            let fallback = try JSONEncoder().encode(credential).base64EncodedString()
            try ImmichClient.removeAccountCache(apiURL: services.client.apiURL, userID: "offline-" + fallback)
        }
        try ImmichClient.removeAccountCache(apiURL: services.client.apiURL, userID: services.cacheUserID)
        if let id = services.user?.id, id != services.cacheUserID {
            try ImmichClient.removeAccountCache(apiURL: services.client.apiURL, userID: id)
        }
    }

    private func start(client: ImmichClient, user: User?, cacheUserID: String) {
        let isolated = client.accountIsolated(userID: cacheUserID)
        let services = AccountServices(client: isolated, user: user, cacheUserID: cacheUserID)
        let legacyCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageCache", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: legacyCache.path) { try FileManager.default.removeItem(at: legacyCache) }
        } catch { accountError = error.localizedDescription }
        services.onUnauthorized = { [weak self, weak services] in
            Task {
                guard let self, self.services === services else { return }
                await self.signOut()
            }
        }
        services.onUserLoaded = { [weak self, weak services] user in
            guard let self, self.services === services, !self.switching, let credential = client.credential else { return }
            do {
                try AccountVault.save(account: .init(serverURL: client.serverURL, apiURL: client.apiURL, credential: credential), user: user)
                try self.refreshEntries()
                self.currentAccountID = client.apiURL.absoluteString + "|" + user.id
            } catch { self.accountError = error.localizedDescription }
        }
        self.services?.upload.cancelAll() // Upload: the previous account's queue goes away with its services.
        phase = .signedIn(services)
        Task { await services.bootstrap() }
    }
}

/// Everything that belongs to one signed-in server/user.
@MainActor @Observable
final class AccountServices {
    let client: ImmichClient
    let sharing: SharingModel // Sharing
    let upload: UploadQueue // Upload
    let metadata = MetadataSharedState()
    let pipeline: ImagePipeline
    private(set) var user: User?
    private(set) var features = ServerFeatures()
    private(set) var version: ServerVersion?
    private(set) var albums: [Album] = []
    private(set) var preferences: AccountPreferences? // Account: loaded preferences for feature consumers.
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

    let cacheUserID: String
    @ObservationIgnored var onUserLoaded: (User) -> Void = { _ in }
    @ObservationIgnored var onUnauthorized: () -> Void = {}
    @ObservationIgnored let windows = NSHashTable<LibrarySession>.weakObjects()

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

    var notifications: [AccountNotification] = []
    var notificationsAvailable = true
    @ObservationIgnored var notificationTask: Task<Void, Never>?
    func reloadNotifications() async throws {
        notifications = try await client.accountNotifications().sorted { $0.createdAt > $1.createdAt }
    }
    func startNotifications() {
        notificationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await self?.reloadNotifications() }
                catch ImmichError.http(404, _), ImmichError.http(403, _) { self?.notificationsAvailable = false; return }
                catch { self?.handle(error) }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    func bootstrap() async {
        startNotifications()
        async let features = try? client.serverFeatures()
        async let version = try? client.serverVersion()
        async let user = try? client.currentUser()
        self.features = await features ?? ServerFeatures()
        self.version = await version
        if let user = await user { self.user = user; onUserLoaded(user) }
        preferences = try? await client.accountPreferences()
        await reloadAlbums()
        await sharing.reload() // Sharing
        await loadExploreTags()
    }

    var preferencesRevision = 0
    func setPreferences(_ value: AccountPreferences) {
        preferences = value
        preferencesRevision += 1
        Task { await loadExploreTags(refresh: true); await sharing.reload() }
    }

    func refreshAccountUser() async throws { user = try await client.currentUser() }

    func reloadAlbums() async {
        do {
            albums = try await client.albumCollections(legacy: (version?.major ?? 3) < 3).sorted { // Albums
                ($0.lastModifiedAssetTimestamp ?? "") > ($1.lastModifiedAssetTimestamp ?? "")
            }
        } catch { handle(error) }
    }

    func invalidateGrids() {
        for window in windows.allObjects { window.invalidateMacWindowGrids() }
    }

    func removeFromGrids(_ ids: Set<String>) {
        for window in windows.allObjects { window.removeFromGrids(ids) }
        MacQuickLook.shared.dismiss()
    }

    func handle(_ error: Error) {
        if case ImmichError.unauthorized = error { onUnauthorized() }
    }
}

/// Navigation, selection and presentations belong to one window.
@MainActor @Observable
final class LibrarySession {
    let services: AccountServices
    let albumActions = AlbumsActions()
    let metadata: MetadataState
    let sharing: SharingModel
    @ObservationIgnored private var gridModels: [GridSource: AssetGridModel] = [:]
    var client: ImmichClient { services.client }
    var pipeline: ImagePipeline { services.pipeline }
    var upload: UploadQueue { services.upload }
    var user: User? { services.user }
    var features: ServerFeatures { services.features }
    var version: ServerVersion? { services.version }
    var albums: [Album] { services.albums }
    var preferences: AccountPreferences? { services.preferences }
    var preferencesRevision: Int { services.preferencesRevision }
    var exploreTags: [ExploreTag] { services.exploreTags }
    var exploreTagsEnabled: Bool { services.exploreTagsEnabled }
    var cacheUserID: String { services.cacheUserID }
    init(services: AccountServices) {
        self.services = services
        metadata = MetadataState(shared: services.metadata)
        sharing = SharingModel(client: services.client, data: services.sharing.data)
        services.windows.add(self)
    }
    func reloadAlbums() async { await services.reloadAlbums() }
    func loadExploreTags(refresh: Bool = false) async { await services.loadExploreTags(refresh: refresh) }
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

    var macGridRevision = 0

    func invalidateMacWindowGrids() {
        for model in gridModels.values { model.markStale() }
        macGridRevision += 1
    }

    /// Mutations affect cached grids in every window for this account.
    func invalidateGrids(except keep: AssetGridModel? = nil) {
        for model in gridModels.values where model !== keep { model.markStale() }
        macGridRevision += 1
        for window in services.windows.allObjects where window !== self { window.invalidateMacWindowGrids() }
    }

    // Explore
    func exploreRemoveFromGrids(_ ids: Set<String>) {
        services.removeFromGrids(ids)
    }

    func removeFromGrids(_ ids: Set<String>) {
        for model in gridModels.values {
            model.exploreRemove(ids)
            if let id = model.viewerID, ids.contains(id) { model.viewerID = nil }
        }
    }

    func handle(_ error: Error) {
        services.handle(error)
    }
}
