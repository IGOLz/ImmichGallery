import Foundation

// Duplicates: the server sends every group at once, so the app can sort them. Immich's web app keeps the
// server's order; the other orders put the groups worth reviewing first.

enum DuplicatesSortBy: String, CaseIterable, Identifiable {
    case server = "Default", itemCount = "ItemCount", totalSize = "TotalSize"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .server: "Default Order"
        case .itemCount: "Most Items"
        case .totalSize: "Largest Size"
        }
    }
}

struct DuplicatesArrangement {
    var sortBy = DuplicatesSortBy.server

    /// Most items or largest first. Ties keep the server's order.
    func sorted(_ groups: [AssetsDuplicate]) -> [AssetsDuplicate] {
        let key: (AssetsDuplicate) -> Int64
        switch sortBy {
        case .server: return groups
        case .itemCount: key = { Int64($0.assets.count) }
        case .totalSize: key = { $0.assets.reduce(0) { $0 + ($1.exifInfo?.fileSizeInByte ?? 0) } }
        }
        return groups.enumerated()
            .sorted { a, b in
                let x = key(a.element), y = key(b.element)
                return x != y ? x > y : a.offset < b.offset
            }
            .map(\.element)
    }
}
