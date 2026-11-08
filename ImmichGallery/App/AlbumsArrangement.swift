import Foundation

// Albums: the Immich web app's album view settings (web/src/lib/utils/album-utils.ts and
// AlbumsList.svelte). Albums are filtered, grouped, then sorted within each group.

enum AlbumsSortOrder: String, CaseIterable, Identifiable {
    case ascending = "asc", descending = "desc"
    var id: Self { self }
    var title: LocalizedStringResource { self == .ascending ? "Ascending" : "Descending" }
}

enum AlbumsFilter: String, CaseIterable, Identifiable {
    case all = "All", owned = "Owned", shared = "Shared"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All Albums"
        case .owned: "My Albums"
        case .shared: "Shared Albums"
        }
    }
}

enum AlbumsGroupBy: String, CaseIterable, Identifiable {
    case none = "None", year = "Year", owner = "Owner"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .none: "No Grouping"
        case .year: "Year"
        case .owner: "Owner"
        }
    }
    var defaultOrder: AlbumsSortOrder { self == .year ? .descending : .ascending }
}

enum AlbumsSortBy: String, CaseIterable, Identifiable {
    case title = "Title", itemCount = "ItemCount", dateModified = "DateModified", dateCreated = "DateCreated"
    case mostRecentPhoto = "MostRecentPhoto", oldestPhoto = "OldestPhoto"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .title: "Title"
        case .itemCount: "Item Count"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .mostRecentPhoto: "Most Recent Photo"
        case .oldestPhoto: "Oldest Photo"
        }
    }
    var defaultOrder: AlbumsSortOrder { self == .title ? .ascending : .descending }
}

struct AlbumsGroup: Identifiable {
    enum Header: Hashable {
        case year(Int), unknownYear, mine, owner(String)
    }
    let id: String
    let header: Header?
    var albums: [Album]
}

struct AlbumsArrangement {
    var filter = AlbumsFilter.all
    var groupBy = AlbumsGroupBy.year
    var groupOrder = AlbumsSortOrder.descending
    var sortBy = AlbumsSortBy.mostRecentPhoto
    var sortOrder = AlbumsSortOrder.descending

    /// Immich turns year groups off while sorting by album dates, which say nothing about the photos' years.
    func allows(_ option: AlbumsGroupBy) -> Bool {
        option != .year || ![.dateCreated, .dateModified].contains(sortBy)
    }

    var effectiveGroupBy: AlbumsGroupBy { allows(groupBy) ? groupBy : .none }

    func groups(_ albums: [Album], userID: String?) -> [AlbumsGroup] {
        let shown = albums.filter { album in
            switch filter {
            case .all: true
            case .owned: Self.ownerID(album) == userID
            case .shared: album.shared
            }
        }
        guard !shown.isEmpty else { return [] }
        let groups: [AlbumsGroup]
        switch effectiveGroupBy {
        case .none:
            groups = [AlbumsGroup(id: "albums", header: nil, albums: shown)]
        case .year:
            // The newest photo decides the year, or the oldest when sorting by it. The server sends
            // the photo's own wall-clock date at UTC midnight, so the year is read in UTC.
            let years = Dictionary(grouping: shown) { album -> Int? in
                (sortBy == .oldestPhoto ? album.startDate : album.endDate)
                    .flatMap(ImmichDate.parse).map { Self.utc.component(.year, from: $0) }
            }
            groups = Self.ordered(Array(years), groupOrder, key: { $0.key }).map { year, albums in
                AlbumsGroup(id: year.map { "year-\($0)" } ?? "year-unknown", header: year.map { .year($0) } ?? .unknownYear, albums: albums)
            }
        case .owner:
            // Your own albums come first in ascending order and last in descending order.
            let owners = Dictionary(grouping: shown) { Self.ownerID($0) ?? "" }
            let others = Self.ordered(Array(owners.filter { $0.key != userID }), groupOrder,
                                      key: { $0.value.first?.albumOwner?.name ?? "" }, compare: { $0.localizedCompare($1) })
                .map { id, albums in AlbumsGroup(id: "owner-\(id)", header: .owner(albums.first?.albumOwner?.name ?? ""), albums: albums) }
            let mine = userID.flatMap { owners[$0] }.map { [AlbumsGroup(id: "owner-mine", header: .mine, albums: $0)] } ?? []
            groups = groupOrder == .ascending ? mine + others : others + mine
        }
        return groups.map { group in
            var group = group
            group.albums = sorted(group.albums)
            return group
        }
    }

    func sorted(_ albums: [Album]) -> [Album] {
        let date = { (value: String?) in value.flatMap(ImmichDate.parse) }
        return switch sortBy {
        case .title: Self.ordered(albums, sortOrder, key: \.albumName, compare: { $0.localizedCompare($1) })
        case .itemCount: Self.ordered(albums, sortOrder, key: \.assetCount)
        case .dateModified: Self.ordered(albums, sortOrder, key: { date($0.updatedAt) })
        case .dateCreated: Self.ordered(albums, sortOrder, key: { date($0.createdAt) })
        case .mostRecentPhoto: Self.ordered(albums, sortOrder, key: { date($0.endDate) })
        case .oldestPhoto: Self.ordered(albums, sortOrder, key: { date($0.startDate) })
        }
    }

    private static func ownerID(_ album: Album) -> String? { album.albumOwner?.id ?? album.ownerId }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func ordered<Element, Key: Comparable>(_ elements: [Element], _ order: AlbumsSortOrder,
                                                          key: (Element) -> Key?) -> [Element] {
        ordered(elements, order, key: key, compare: { $0 < $1 ? .orderedAscending : $0 > $1 ? .orderedDescending : .orderedSame })
    }

    /// A stable sort. Elements without a key stay last in either order, like Immich's albums without photos.
    private static func ordered<Element, Key>(_ elements: [Element], _ order: AlbumsSortOrder, key: (Element) -> Key?,
                                              compare: (Key, Key) -> ComparisonResult) -> [Element] {
        elements.enumerated().map { (offset: $0.offset, element: $0.element, key: key($0.element)) }
            .sorted { a, b in
                switch (a.key, b.key) {
                case let (x?, y?):
                    let result = compare(x, y)
                    if result == .orderedSame { return a.offset < b.offset }
                    return result == (order == .ascending ? .orderedAscending : .orderedDescending)
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.offset < b.offset
                }
            }
            .map(\.element)
    }
}
