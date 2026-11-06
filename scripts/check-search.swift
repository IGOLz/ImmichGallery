// Run from the repository root:
// swiftc -parse-as-library ImmichGallery/API/{Models,Models+Search,ImmichClient,ImmichClient+Search}.swift scripts/check-search.swift -o build/check-search && build/check-search
// Optional argument: folder containing search-live-*.json responses from the demo.
import Foundation
import Synchronization

final class SearchSortProtocol: URLProtocol, @unchecked Sendable {
    static let pages = Mutex<[Int]>([])
    static let failSecondPage = Mutex(false)
    static let repeatPage = Mutex(false)
    static let fallback = Mutex(false)
    static let largePageSize = Mutex<Int?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let page = body["page"] as! Int
        Self.pages.withLock { $0.append(page) }
        let metadata = request.url!.path.hasSuffix("metadata")
        if metadata { assert(body["order"] as? String == "asc") }
        else { assert(body["order"] == nil, "Upstream smart search must not receive unsupported order") }
        let dates = page == 1 ? [("a", "2020-01-01T00:00:00Z"), ("b", "2025-01-01T01:00:00+01:00")] : [("c", "2025-01-01T00:00:00.500Z"), ("d", "2010-01-01T00:00:00Z")]
        var items = dates.map { id, date in
            ["id": id, "type": "IMAGE", "originalFileName": id + ".jpg", "fileCreatedAt": date, "localDateTime": date, "isFavorite": false, "isTrashed": false] as [String: Any]
        }
        if let count = Self.largePageSize.withLock({ $0 }) {
            assert(body["size"] as? Int == 500)
            items = (0..<count).map { offset in
                let rank = (page - 1) * count + offset
                let date = Date(timeIntervalSince1970: Double(rank) * 86400).ISO8601Format()
                return ["id": "rank-\(rank)", "type": "IMAGE", "originalFileName": "photo.jpg", "fileCreatedAt": date, "localDateTime": date, "isFavorite": false, "isTrashed": false]
            }
        }
        var assets: [String: Any] = ["items": items]
        if page == 1 { assets["nextPage"] = "2" }
        if Self.largePageSize.withLock({ $0 != nil }) { assets["nextPage"] = String(page + 1) }
        if Self.repeatPage.withLock({ $0 }) { assets["nextPage"] = "1" }
        let notFound = !metadata && Self.fallback.withLock { $0 }
        let failed = page == 2 && Self.failSecondPage.withLock { $0 }
        let response = HTTPURLResponse(url: request.url!, statusCode: notFound ? 404 : failed ? 500 : 200, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: failed ? ["message": "Page failure"] : ["assets": assets]))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CheckSearch {
    static func main() async throws {
        var query = SearchQuery()
        query.text = "mountains"
        query.country = "Italy"
        query.favorites = true
        query.notInAlbum = true
        query.archived = true
        query.rating = 3
        query.personIDs = ["person-b", "person-a"]
        query.takenAfter = Date(timeIntervalSince1970: 1_700_000_000)
        query.takenBefore = query.takenAfter
        assert(query.validDates)
        func body(_ smart: Bool) throws -> [String: Any] {
            let data = try JSONEncoder().encode(AdvancedSearchRequest(query, smart: smart, page: .init(page: 2)))
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let smart = try body(true)
        assert(smart["withExif"] == nil)
        let start = Calendar.current.startOfDay(for: query.takenAfter!)
        query.takenAfter = start.addingTimeInterval(3600)
        query.takenBefore = start
        assert(query.validDates, "Same calendar day must be valid regardless of time")
        query.personNames = ["person-a": "Alice", "person-b": "Bob"]
        assert(query.chips.contains("Alice, Bob"))
        let original = query
        for chip in original.filterChips {
            var changed = original
            changed.remove(chip.id)
            assert(!changed.filterChips.contains { $0.id == chip.id })
            assert(changed.filterChips.count == original.filterChips.count - 1)
            assert(changed.text == original.text && changed.mode == original.mode)
        }
        for mode in SearchMode.allCases {
            var restored = original
            restored.mode = mode
            restored.clampMode(smartEnabled: false, ocrEnabled: false)
            assert(restored.mode == (mode == .description ? .description : .fileName))
            restored.mode = mode
            restored.clampMode(smartEnabled: true, ocrEnabled: true)
            assert(restored.mode == mode)
        }
        let legacy = try JSONDecoder().decode(SearchQuery.self, from: Data(#"{"text":"cat","personIDs":["person-a"]}"#.utf8))
        assert(legacy.text == "cat" && legacy.personIDs == ["person-a"] && legacy.personNames.isEmpty)
        assert(legacy.mode == .context && !legacy.favorites && legacy.sort == .automatic)
        var filters = original
        filters.state = "Lazio"; filters.make = "Apple"; filters.model = "iPhone"
        for type in ["country", "state", "city", "camera-make", "camera-model", "camera-lens-model"] {
            let params = ImmichClient.searchSuggestionParameters(type, filters: filters).compactMapValues { $0 }
            let expected: Set<String>
            switch type {
            case "state": expected = ["type", "country"]
            case "city": expected = ["type", "country", "state"]
            case "camera-model": expected = ["type", "make"]
            case "camera-lens-model": expected = ["type", "make", "model"]
            default: expected = ["type"]
            }
            assert(Set(params.keys) == expected)
        }
        let features = try JSONDecoder().decode(ServerFeatures.self, from: Data(#"{"ocr":true}"#.utf8))
        assert(features.ocr && !features.smartSearch)

        assert(smart["query"] as? String == "mountains")
        assert(smart["originalFileName"] == nil && smart["order"] == nil)
        assert(smart["isFavorite"] as? Bool == true)
        assert(smart["visibility"] as? String == "archive")
        assert(smart["country"] as? String == "Italy")
        assert(smart["personIds"] as? [String] == ["person-a", "person-b"])
        for (mode, field) in [(SearchMode.fileName, "originalFileName"), (.description, "description"), (.ocr, "ocr")] {
            query.mode = mode
            let metadata = try body(false)
            assert(metadata[field] as? String == "mountains")
            assert(metadata["query"] == nil && metadata["page"] as? Int == 2)
            assert(metadata["rating"] as? Int == 3)
        }
        for sort in SearchSort.allCases {
            query.sort = sort
            let metadata = try body(false)
            let smart = try body(true)
            assert(metadata["order"] as? String == (sort == .oldest ? "asc" : "desc"))
            assert(smart["order"] == nil)
            assert(smart["size"] as? Int == (sort == .automatic ? 100 : 500))
            let restored = try JSONDecoder().decode(SearchQuery.self, from: JSONEncoder().encode(query))
            assert(restored == query)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchSortProtocol.self]
        let url = URL(string: "https://search.invalid/api")!
        let client = ImmichClient(serverURL: url, apiURL: url, credential: nil, session: URLSession(configuration: configuration))
        var sortedQuery = SearchQuery()
        sortedQuery.text = "mountains"
        for (sort, expected) in [(SearchSort.automatic, ["a", "b"]), (.newest, ["c", "b", "a", "d"]), (.oldest, ["d", "a", "b", "c"])] {
            SearchSortProtocol.pages.withLock { $0 = [] }
            sortedQuery.sort = sort
            let result = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1))
            assert(result.items.map(\.id) == expected)
            assert(SearchSortProtocol.pages.withLock { $0 } == (sort == .automatic ? [1] : [1, 2]))
            assert(result.nextPage == (sort == .automatic ? "2" : nil))
        }
        // Lower relevance ranks have newer dates: truncation must happen before sorting.
        // Cover a full first page, a server returning smaller pages, and an oversized response.
        for pageSize in [500, 300, 600] {
            SearchSortProtocol.largePageSize.withLock { $0 = pageSize }
            for sort in [SearchSort.newest, .oldest] {
                sortedQuery.sort = sort
                SearchSortProtocol.pages.withLock { $0 = [] }
                let result = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1)) { count in
                    assert(count <= 500)
                }
                let ranks = sort == .newest ? Array((0..<500).reversed()) : Array(0..<500)
                assert(result.items.map(\.id) == ranks.map { "rank-\($0)" })
                assert(result.nextPage == nil && result.nextCursor == nil)
                assert(SearchSortProtocol.pages.withLock { $0 } == (pageSize < 500 ? [1, 2] : [1]))
            }
        }
        SearchSortProtocol.largePageSize.withLock { $0 = nil }
        SearchSortProtocol.failSecondPage.withLock { $0 = true }
        do {
            _ = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1))
            assertionFailure("An incomplete date-sorted result must not be returned")
        } catch ImmichError.http(500, _) {}
        SearchSortProtocol.failSecondPage.withLock { $0 = false }
        SearchSortProtocol.repeatPage.withLock { $0 = true }
        do {
            _ = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1))
            assertionFailure("Repeated pages must fail")
        } catch ImmichError.http(502, _) {}
        SearchSortProtocol.repeatPage.withLock { $0 = false }
        SearchSortProtocol.fallback.withLock { $0 = true }
        let fallback = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1))
        assert(fallback.items.map(\.id) == ["a", "b"] && fallback.nextPage == "2")
        SearchSortProtocol.fallback.withLock { $0 = false }
        sortedQuery.text = ""
        let metadata = try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1))
        assert(metadata.nextPage == "2")
        sortedQuery.text = "mountains"
        let task = Task {
            try await client.advancedSearch(sortedQuery, smartEnabled: true, page: .init(page: 1)) { count in
                if count > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            assertionFailure("Cancellation must stop collecting pages")
        } catch is CancellationError {} catch let error as URLError where error.code == .cancelled {}
        let data = Data(#"{"assets":{"items":[{"id":"b","type":"IMAGE","originalFileName":"b.jpg","fileCreatedAt":"2025-01-01T00:00:00Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false},{"id":"a","type":"IMAGE","originalFileName":"a.jpg","fileCreatedAt":"2025-01-01T00:00:00.000Z","localDateTime":"2025-01-01T00:00:00Z","isFavorite":false,"isTrashed":false},{"id":"z","type":"IMAGE","originalFileName":"z.jpg","fileCreatedAt":"invalid","localDateTime":"invalid","isFavorite":false,"isTrashed":false}]}}"#.utf8)
        let ties = try JSONDecoder().decode(SearchResponse.self, from: data).assets.items
        for sort in [SearchSort.newest, .oldest] {
            assert(ImmichClient.sortSearchAssets(ties, order: sort).items.map(\.id) == ["a", "b", "z"])
        }
        query.takenBefore = query.takenAfter!.addingTimeInterval(-86400)
        assert(!query.validDates)
        let roundTrip = try JSONDecoder().decode(SearchQuery.self, from: JSONEncoder().encode(query))
        assert(roundTrip == query)
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
                try JSONDecoder().decode(type, from: Data(contentsOf: folder.appendingPathComponent("search-live-\(name).json")))
            }
            _ = try decode("server-features", as: ServerFeatures.self)
            _ = try decode("users-me-preferences", as: SearchPreferences.self)
            _ = try decode("search-suggestions", as: [String].self)
            _ = try decode("search-explore", as: [SearchExploreGroup].self)
            for name in ["search-smart", "search-metadata", "combined-smart", "combined-metadata", "ocr", "description", "filename", "people"] {
                let result = try decode(name, as: SearchResponse.self)
                print("Decoded \(name): \(result.assets.items.count) assets")
            }
        }
        print("Search request and DTO checks passed")
    }
}
