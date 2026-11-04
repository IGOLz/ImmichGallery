// Run from the repository root:
// swiftc -parse-as-library ImmichGallery/API/{Models,Models+Search,ImmichClient,ImmichClient+Search}.swift scripts/check-search.swift -o /tmp/check-search && /tmp/check-search
// Optional argument: folder containing search-live-*.json responses from the demo.
import Foundation

@main struct CheckSearch {
    static func main() throws {
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
        query.takenBefore = query.takenAfter!.addingTimeInterval(-86400)
        assert(!query.validDates)
        let roundTrip = try JSONDecoder().decode(SearchQuery.self, from: JSONEncoder().encode(query))
        assert(roundTrip == query)
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
                try JSONDecoder().decode(type, from: Data(contentsOf: folder.appendingPathComponent("search-live-\(name).json")))
            }
            _ = try decode("server-features", as: SearchCapabilities.self)
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
