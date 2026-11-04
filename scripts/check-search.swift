// Run from the repository root:
// swiftc -parse-as-library ImmichGallery/API/{Models,Models+Search,ImmichClient,ImmichClient+Search}.swift scripts/check-search.swift -o build/check-search && build/check-search
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
        assert(legacy.mode == .context && !legacy.favorites)
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
