import Foundation

/// Duplicates: groups in the server's order, by most items, or by largest total size.
@main struct DuplicatesArrangementChecks {
    static func main() throws {
        let asset = { (id: String, size: Int) in
            #"{"id":"\#(id)", "type":"IMAGE", "originalFileName":"\#(id).jpg", "fileCreatedAt":"", "localDateTime":"", "isFavorite":false, "isTrashed":false, "exifInfo":{"fileSizeInByte":\#(size)}}"#
        }
        let json = """
        [
          {"duplicateId":"a", "assets":[\(asset("a1", 10)), \(asset("a2", 10))]},
          {"duplicateId":"b", "assets":[\(asset("b1", 5)), \(asset("b2", 5)), \(asset("b3", 5))]},
          {"duplicateId":"c", "assets":[\(asset("c1", 900)), \(asset("c2", 100))]},
          {"duplicateId":"d", "assets":[\(asset("d1", 1)), \(asset("d2", 1)), \(asset("d3", 1))]}
        ]
        """
        let groups = try JSONDecoder().decode([AssetsDuplicate].self, from: Data(json.utf8))
        let ids = { (sortBy: DuplicatesSortBy) in DuplicatesArrangement(sortBy: sortBy).sorted(groups).map(\.id) }

        precondition(ids(.server) == ["a", "b", "c", "d"])
        // Ties keep the server's order.
        precondition(ids(.itemCount) == ["b", "d", "a", "c"])
        precondition(ids(.totalSize) == ["c", "a", "b", "d"])
        precondition(DuplicatesSortBy(rawValue: "TotalSize") == .totalSize)
        print("Duplicates sorting checks passed.")
    }
}
