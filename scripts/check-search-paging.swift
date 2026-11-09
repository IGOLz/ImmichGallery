// Offline harness. Run from the repository root:
// python3 scripts/check-integration.py compiles this harness with production account services and grids.
import Foundation
import Synchronization

// Vault and UI stand-ins fail closed: this executable cannot read credentials or launch the app.
struct AccountStore {
    struct Account { let serverURL: URL; let apiURL: URL; let credential: Credential }
}
enum AccountVault {
    struct Entry { let id: String; let account: AccountStore.Account; let userID: String }
    static var legacyAccountForMigration: AccountStore.Account? { nil }
    @MainActor static var restoreReads = 0
    @MainActor static func loadEntries() throws -> [Entry] { restoreReads += 1; return [] }
    static func selectedEntry() throws -> Entry? { nil }
    static func remove(_ id: String) throws { fatalError("No credential access") }
    static func select(_ id: String) throws { fatalError("No credential access") }
    static func save(account: AccountStore.Account, user: User) throws { fatalError("No credential access") }
}
@MainActor final class MacIntegrationRouter {
    static let shared = MacIntegrationRouter()
    weak var app: AppModel?
    var pending: [String] = []
    var widgetLinks: [String] = []
}
@MainActor final class MacQuickLook {
    static let shared = MacQuickLook()
    func dismiss() {}
}
struct SharingPresentation {}
@MainActor final class WidgetFeedUpdater {
    static let shared = WidgetFeedUpdater()
    func start(_ services: AccountServices) {}
    func clear() {}
}

final class PagingProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex(0)
    static let completeSearch = Mutex(false)
    static let filteredLibrary = Mutex(false)
    static let delayPage = Mutex(false)
    static let delayed = Mutex<PagingProtocol?>(nil)
    private var delayedData: Data?

    func finishDelayed() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: delayedData!)
        client!.urlProtocolDidFinishLoading(self)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.httpMethod == "GET" {
            let features = request.url!.path.hasSuffix("server/features")
            let response = HTTPURLResponse(url: request.url!, statusCode: features ? 200 : 404, httpVersion: nil, headerFields: nil)!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: Data((features ? #"{"smartSearch":true}"# : #"{"message":"Not available"}"#).utf8))
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        Self.requests.withLock { $0 += 1 }
        if request.url!.path.hasSuffix("search/large-assets") {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            assert(!query.contains { $0.name == "isFavorite" }, "Boolean strings fail the large-assets query DTO")
            assert(query.contains { $0.name == "type" && $0.value == "IMAGE" })
            let data = Data(#"[{"id":"large-favorite","ownerId":"owner","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01","localDateTime":"2025-01-01","isFavorite":true,"isTrashed":false},{"id":"large-other","ownerId":"owner","type":"IMAGE","originalFileName":"b.jpg","fileCreatedAt":"2025-01-01","localDateTime":"2025-01-01","isFavorite":false,"isTrashed":false}]"#.utf8)
            client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: data)
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        if request.httpMethod == "PUT", request.url!.path.hasSuffix("assets") {
            client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        var requestData = request.httpBody ?? Data()
        if requestData.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                requestData.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = try! JSONSerialization.jsonObject(with: requestData) as! [String: Any]
        if Self.filteredLibrary.withLock({ $0 }) {
            assert(body["type"] as? String == "IMAGE")
            assert(body["visibility"] as? String == "timeline")
            let page = body["page"] as! Int
            let item: [String: Any] = ["id": "filtered-\(page)", "ownerId": "owner", "type": "IMAGE",
                "originalFileName": "a.jpg", "fileCreatedAt": "2025-01-01T00:00:00Z",
                "localDateTime": "2025-01-01T00:00:00Z", "isFavorite": body["isFavorite"] as? Bool ?? false, "isTrashed": false,
                "visibility": page == 2 ? "hidden" : "timeline"]
            var assets: [String: Any] = ["items": [item]]
            if page < 3 { assets["nextPage"] = String(page + 1) }
            let data = try! JSONSerialization.data(withJSONObject: ["assets": assets])
            if page == 2, Self.delayPage.withLock({ $0 }) {
                delayedData = data
                Self.delayed.withLock { $0 = self }
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: data)
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        if body["isFavorite"] as? Bool == true || body["filter"] != nil {
            assert(body["withExif"] as? Bool == true, "Ranking needs EXIF file sizes")
            let modern = body["filter"] != nil
            if modern {
                let filter = body["filter"] as! [String: Any]
                assert((filter["isFavorite"] as! [String: Bool])["eq"] == true)
                assert((filter["type"] as! [String: String])["eq"] == "IMAGE")
                assert((body["orderBy"] as! [String: String])["field"] == "fileSizeInBytes")
                assert(body["type"] == nil && body["order"] == nil, "New and legacy shapes cannot be mixed")
            }
            let second = body["page"] as? Int == 2
            let item: [String: Any] = ["id": second ? "larger-favorite" : "large-favorite", "ownerId": "owner", "type": "IMAGE",
                "originalFileName": "a.jpg", "fileCreatedAt": "2025-01-01", "localDateTime": "2025-01-01",
                "isFavorite": true, "isTrashed": false, "exifInfo": ["fileSizeInByte": second ? 1000 : 500]]
            var assets: [String: Any] = ["items": [item]]
            if !modern && !second { assets["nextPage"] = "2" }
            client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["assets": assets]))
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        if body["type"] as? String == "VIDEO" {
            assert(body["visibility"] as? String == "timeline", "Videos must exclude hidden Live Photo components and archived assets on every page")
        } else {
            assert(body["visibility"] == nil, "Filename and advanced searches must retain their own visibility rules")
        }
        let firstPage = body["page"] as? Int == 1
        let data = Data((firstPage ? #"{"assets":{"items":[{"id":"asset-a","ownerId":"owner","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01T00:00:00Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false}],"nextPage":"2"}}"# : #"{"message":"Simulated page failure"}"#).utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: firstPage ? 200 : 500, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var responseData = data
        if Self.completeSearch.withLock({ $0 }) {
            var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            var assets = object["assets"] as! [String: Any]
            assets.removeValue(forKey: "nextPage")
            var items = assets["items"] as! [[String: Any]]
            var locked = items[0]
            locked["id"] = "locked-asset"; locked["visibility"] = "locked"
            items.append(locked)
            assets["items"] = items; object["assets"] = assets
            responseData = try! JSONSerialization.data(withJSONObject: object)
        }
        client!.urlProtocol(self, didLoad: responseData)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CheckSearchPaging {
    @MainActor static func main() async throws {
        assert(GridSource.geolocation.excludesArchived && GridSource.largeFiles.excludesArchived)
        assert(!GridSource.explore(.tag("tag")).excludesArchived)
        let app = AppModel()
        async let firstRestore: Void = app.restore()
        async let secondRestore: Void = app.restore()
        _ = await (firstRestore, secondRestore)
        assert(AccountVault.restoreReads == 1)
        guard case .signedOut = app.phase else { fatalError("Empty test vault must sign out") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagingProtocol.self]
        let url = URL(string: "https://demo.immich.app/api")!
        let client = ImmichClient(serverURL: url, apiURL: url, credential: nil, session: URLSession(configuration: config))
        defer { client.session.invalidateAndCancel() }
        let user = User(id: "owner", email: "", name: "")
        let services = AccountServices(client: client, user: user, cacheUserID: "test")
        let passwordUser = User(id: "password-test", email: "", name: "", shouldChangePassword: true, isAdmin: false)
        for credential: Credential? in [.accessToken("test"), .apiKey("test"), nil] {
            let passwordClient = ImmichClient(serverURL: url, apiURL: url, credential: credential, session: client.session)
            let passwordServices = AccountServices(client: passwordClient, user: passwordUser, cacheUserID: "password-test")
            assert(passwordServices.requiresPasswordChange == (credential == .accessToken("test")))
            let unknownUserServices = AccountServices(client: passwordClient, user: nil, cacheUserID: "password-test")
            assert(!unknownUserServices.requiresPasswordChange)
        }
        let session = LibrarySession(services: services)
        let secondWindow = LibrarySession(services: services)
        assert(session.pipeline === secondWindow.pipeline && session.upload === secondWindow.upload)
        assert(session.metadata !== secondWindow.metadata && session.sharing !== secondWindow.sharing)
        session.albumActions.newAlbum()
        assert(!secondWindow.albumActions.creating)
        session.metadata.imageRevision += 1
        assert(secondWindow.metadata.imageRevision == 1)
        session.sharing.linksAvailable = false
        assert(!secondWindow.sharing.linksAvailable)
        for source in [GridSource.videos, .search("cat"), .filteredSearch(SearchQuery())] {
            PagingProtocol.requests.withLock { $0 = 0 }
            let model = session.gridModel(for: source)
            await model.reload()
            assert(model.totalCount == 1 && model.state == .loaded)
            assert(model.canMutate(["asset-a"]) && !model.canMutate(["unknown"]) && !model.canMutate([]))
            assert(!session.gridModel(for: .trash).canMutate(["asset-a"]))
            model.cellAppeared(section: 0, item: 0)
            for _ in 0..<100 where model.lastError == nil { try await Task.sleep(for: .milliseconds(10)) }
            assert(model.lastError != nil)
            model.lastError = nil
            for _ in 0..<20 { model.cellAppeared(section: 0, item: 0) }
            let neighbor = await model.neighbor(of: "asset-a", delta: 1)
            assert(neighbor == nil)
            try await Task.sleep(for: .milliseconds(20))
            assert(PagingProtocol.requests.withLock { $0 } == 2 && model.lastError == nil)
            await model.reload()
            model.cellAppeared(section: 0, item: 0)
            for _ in 0..<100 where model.lastError == nil { try await Task.sleep(for: .milliseconds(10)) }
            assert(model.lastError != nil && PagingProtocol.requests.withLock { $0 } == 4)
        }
        await services.bootstrap()
        services.notificationTask?.cancel()
        assert(session.features.smartSearch)
        PagingProtocol.completeSearch.withLock { $0 = true }
        var sortedQuery = SearchQuery()
        sortedQuery.text = "cached"
        sortedQuery.sort = .newest
        let newest = session.gridModel(for: .filteredSearch(sortedQuery))
        await newest.reload()
        assert(newest.state == .loaded && newest.totalCount == 1)
        let requestCount = PagingProtocol.requests.withLock { $0 }
        sortedQuery.sort = .oldest
        let oldest = session.gridModel(for: .filteredSearch(sortedQuery))
        await oldest.loadIfNeeded()
        assert(oldest.state == .loaded && oldest.totalCount == 1)
        assert(PagingProtocol.requests.withLock { $0 } == requestCount, "Changing date direction must reuse completed results")
        await oldest.reload()
        assert(PagingProtocol.requests.withLock { $0 } == requestCount + 1, "Refresh must bypass the reused results")
        PagingProtocol.completeSearch.withLock { $0 = false }
        let foreignServices = AccountServices(client: client, user: User(id: "other", email: "", name: ""), cacheUserID: "foreign")
        let foreignWindow = LibrarySession(services: foreignServices)
        let foreignGrid = foreignWindow.gridModel(for: .search("cat"))
        await foreignGrid.reload()
        assert(!foreignGrid.canMutate(["asset-a"]) && !foreignGrid.canDelete(["asset-a"]))
        let columns = try JSONDecoder().decode(TimeBucketAssets.self, from: Data(#"{"id":["public","private"],"visibility":["timeline","locked"],"ownerId":["owner","owner"],"isImage":[true,true],"isFavorite":[false,false],"isTrashed":[false,false],"thumbhash":[null,null],"ratio":[1,1],"duration":[null,null],"fileCreatedAt":["2026-01-01","2026-01-01"],"livePhotoVideoId":[null,null]}"#.utf8))
        assert(AssetItem.from(columns).map(\.id) == ["public"])
        let library = session.gridModel(for: .library)
        // Reveal must page past a fully hidden page, also when the target shares a loaded month.
        let mediaKey = GridPage.library.key("mediaType")
        let savedMedia = UserDefaults.standard.object(forKey: mediaKey)
        defer { UserDefaults.standard.set(savedMedia, forKey: mediaKey) }
        UserDefaults.standard.set(GridMediaType.photos.rawValue, forKey: mediaKey)
        PagingProtocol.filteredLibrary.withLock { $0 = true }
        await library.reload()
        assert(library.totalCount == 1)
        let target = try JSONDecoder().decode(AssetResponse.self, from: Data(#"{"id":"filtered-3","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01T00:00:00Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false}"#.utf8))
        let beforeReveal = PagingProtocol.requests.withLock { $0 }
        let video = try JSONDecoder().decode(AssetResponse.self, from: Data(#"{"id":"video","type":"VIDEO","originalFileName":"a.mp4","fileCreatedAt":"2025-01-01","localDateTime":"2025-01-01","isFavorite":false,"isTrashed":false}"#.utf8))
        try await library.loadForReveal(video)
        assert(PagingProtocol.requests.withLock { $0 } == beforeReveal, "An excluded media type must not scan the library")
        try await library.loadForReveal(target)
        assert(library.item(target.id) != nil && library.totalCount == 2)
        assert(library.item("filtered-2") == nil)
        // A page started by reveal must not append into a newer arrangement after reloading.
        await library.reload()
        PagingProtocol.delayPage.withLock { $0 = true }
        let reveal = Task { try await library.loadForReveal(target) }
        for _ in 0..<100 where PagingProtocol.delayed.withLock({ $0 == nil }) { try await Task.sleep(for: .milliseconds(10)) }
        let delayed = PagingProtocol.delayed.withLock { value in let result = value; value = nil; return result }!
        let showKey = GridPage.library.key("show")
        let savedShow = UserDefaults.standard.object(forKey: showKey)
        defer { UserDefaults.standard.set(savedShow, forKey: showKey) }
        UserDefaults.standard.set(GridShow.favorites.rawValue, forKey: showKey)
        await library.reload()
        delayed.finishDelayed()
        do { try await reveal.value; assertionFailure("Stale reveal should cancel") } catch is CancellationError {}
        assert(library.totalCount == 1 && library.item(target.id) == nil)
        let beforeExcluded = PagingProtocol.requests.withLock { $0 }
        try await library.loadForReveal(target)
        assert(PagingProtocol.requests.withLock { $0 } == beforeExcluded, "Non-favorites must not scan a favorites-filtered library")
        await library.setFavorite(["filtered-1"], false)
        assert(library.totalCount == 0, "Unfavoriting must remove an item from a favorites-filtered grid")
        UserDefaults.standard.set(savedShow, forKey: showKey)
        PagingProtocol.delayPage.withLock { $0 = false }
        PagingProtocol.filteredLibrary.withLock { $0 = false }
        UserDefaults.standard.set(savedMedia, forKey: mediaKey)
        let largeFavorites = try await client.assetsLargeFiles(type: "IMAGE", isFavorite: true)
        assert(largeFavorites.map(\.id) == ["larger-favorite", "large-favorite"], "Legacy ranking must include matching favorites from later pages")
        let modernFavorites = try await client.assetsLargeFiles(type: "IMAGE", isFavorite: true, serverVersion: .init(major: 3, minor: 3, patch: 5))
        assert(modernFavorites.map(\.id) == ["large-favorite"])
        let largeAll = try await client.assetsLargeFiles(type: "IMAGE")
        assert(largeAll.count == 2)
        var query = SearchQuery()
        query.text = "first"
        weak let previous = session.gridModel(for: .filteredSearch(query))
        assert(previous != nil)
        query.text = "second"
        let current = session.gridModel(for: .filteredSearch(query))
        assert(previous == nil, "Previous searches must be evicted")
        assert(session.gridModel(for: .filteredSearch(query)) === current)
        assert(session.gridModel(for: .library) === library)
        let firstPrivateGrid = session.gridModel(for: .search("privacy"))
        let secondPrivateGrid = secondWindow.gridModel(for: .search("privacy"))
        await firstPrivateGrid.reload()
        await secondPrivateGrid.reload()
        firstPrivateGrid.open("asset-a")
        secondPrivateGrid.open("asset-a")
        var closedViewers = 0
        session.closeViewer = { closedViewers += 1 }
        secondWindow.closeViewer = { closedViewers += 1 }
        services.removeFromGrids(["asset-a"])
        assert(closedViewers == 2 && firstPrivateGrid.viewerID == nil && secondPrivateGrid.viewerID == nil)
        assert(services.hiddenAssetIDs == ["asset-a"])
        // Locked Folder: its own grid source, uncached client, pipeline and files. Access errors check the unlock
        // instead of signing out, and discarding removes the files.
        assert(AssetItem.from(columns, includingLocked: true).map(\.id) == ["public", "private"])
        assert(GridSource.locked.timelineQuery?.visibility == "locked" && !GridSource.locked.excludesArchived)
        let lockedMedia = LockedFolderMedia(account: client)
        let lockedWindow = LibrarySession(services: services, lockedFolder: lockedMedia)
        assert(!lockedWindow.gridModel(for: .locked).isPaged)
        assert(lockedWindow.client === lockedMedia.client && lockedWindow.pipeline === lockedMedia.pipeline)
        assert(lockedWindow.pipeline !== session.pipeline && session.client === client)
        assert(lockedMedia.client.session.configuration.urlCache == nil)
        let lockedRoot = lockedMedia.client.transferRoot!
        assert(lockedRoot.deletingLastPathComponent().standardizedFileURL.path == MacTransferCache.lockedRoot.standardizedFileURL.path)
        assert(lockedMedia.client.with(credential: .accessToken("renewed")).transferRoot == lockedRoot)
        var lockedFailures = 0, signOuts = 0
        lockedMedia.onRequestFailed = { lockedFailures += 1 }
        services.onUnauthorized = { signOuts += 1 }
        lockedWindow.handle(ImmichError.unauthorized(nil))
        lockedWindow.handle(CancellationError())
        assert(lockedFailures == 1 && signOuts == 0)
        session.handle(ImmichError.unauthorized(nil))
        assert(signOuts == 1)
        services.onUnauthorized = {}
        try FileManager.default.createDirectory(at: lockedRoot.appendingPathComponent("Previews"), withIntermediateDirectories: true)
        lockedMedia.discard()
        assert(!FileManager.default.fileExists(atPath: lockedRoot.path))
        assert(lockedMedia.isDiscarded)
        lockedMedia.requestFailed()
        assert(lockedFailures == 1, "Discarded media must not launch another status check")
        do {
            _ = try MacTransferCache.create(preview: true, root: lockedRoot)
            assertionFailure("A late download must not recreate private files after lock")
        } catch is CancellationError {}
        assert(!FileManager.default.fileExists(atPath: lockedRoot.path))
        print("Offline paging, concurrent restore, shared services, local presentation, ownership and locked visibility checks passed")
    }
}
