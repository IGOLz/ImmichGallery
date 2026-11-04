// Offline harness. Run from the repository root:
// swiftc -parse-as-library ImmichGallery/API/{Models,Models+Search,ImmichClient,ImmichClient+Search}.swift ImmichGallery/App/{AppModel,AssetGridModel}.swift ImmichGallery/Support/Formatters.swift scripts/check-search-paging.swift -o build/check-search-paging && build/check-search-paging
import Foundation
import Synchronization

// Fail closed if the harness ever tries to restore credentials or use an image pipeline.
struct AccountStore {
    struct Account { let serverURL: URL; let apiURL: URL; let credential: Credential }
    static func load() -> Account? { fatalError("Credential access is forbidden in this harness") }
    static func save(_ account: Account) { fatalError("Credential access is forbidden in this harness") }
    static func clear() { fatalError("Credential access is forbidden in this harness") }
}
final class ImagePipeline {
    init(client: ImmichClient) {}
    func removeAll() { fatalError("Image pipeline is unused in this harness") }
}

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
        let data = Data((firstPage ? #"{"assets":{"items":[{"id":"asset-a","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01T00:00:00Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false}],"nextPage":"2"}}"# : #"{"message":"Simulated page failure"}"#).utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: firstPage ? 200 : 500, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CheckSearchPaging {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagingProtocol.self]
        let url = URL(string: "https://demo.immich.app/api")!
        let client = ImmichClient(serverURL: url, apiURL: url, credential: nil, session: URLSession(configuration: config))
        defer { client.session.invalidateAndCancel() }
        let session = LibrarySession(client: client, user: nil)
        for source in [GridSource.videos, .search("cat"), .filteredSearch(SearchQuery())] {
            PagingProtocol.requests.withLock { $0 = 0 }
            let model = session.gridModel(for: source)
            await model.reload()
            assert(model.totalCount == 1 && model.state == .loaded)
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
        print("Offline paging retry and search-cache checks passed")
    }
}
