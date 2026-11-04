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
}
@MainActor final class MacQuickLook {
    static let shared = MacQuickLook()
    func dismiss() {}
}
struct SharingPresentation {}

final class PagingProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
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
        let firstPage = body["page"] as? Int == 1
        let data = Data((firstPage ? #"{"assets":{"items":[{"id":"asset-a","ownerId":"owner","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01T00:00:00Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false}],"nextPage":"2"}}"# : #"{"message":"Simulated page failure"}"#).utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: firstPage ? 200 : 500, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
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
        let foreignServices = AccountServices(client: client, user: User(id: "other", email: "", name: ""), cacheUserID: "foreign")
        let foreignWindow = LibrarySession(services: foreignServices)
        let foreignGrid = foreignWindow.gridModel(for: .search("cat"))
        await foreignGrid.reload()
        assert(!foreignGrid.canMutate(["asset-a"]) && !foreignGrid.canDelete(["asset-a"]))
        let columns = try JSONDecoder().decode(TimeBucketAssets.self, from: Data(#"{"id":["public","private"],"visibility":["timeline","locked"],"ownerId":["owner","owner"],"isImage":[true,true],"isFavorite":[false,false],"isTrashed":[false,false],"thumbhash":[null,null],"ratio":[1,1],"duration":[null,null],"fileCreatedAt":["2026-01-01","2026-01-01"],"livePhotoVideoId":[null,null]}"#.utf8))
        assert(AssetItem.from(columns).map(\.id) == ["public"])
        let library = session.gridModel(for: .library)
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
        print("Offline paging, concurrent restore, shared services, local presentation, ownership and locked visibility checks passed")
    }
}
