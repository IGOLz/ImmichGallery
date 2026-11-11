import Foundation

// Grid pages: view options in the style of Apple Photos. Immich's web app has none for these pages, so
// they stay with what the server filters and orders: the timeline API (GET /timeline/buckets) and, for
// Videos and Large Files, the search API.

/// The grid pages with view options. Each saves its own settings.
enum GridPage: String {
    case library, favorites, archive, partner, person, tag, locked
    case videos, largeFiles, geolocation

    /// A Favorites filter adds nothing on Favorites, and partners' favorites are their own.
    /// Assign Location filters by location instead.
    var offersFavoritesFilter: Bool { ![.favorites, .partner, .geolocation].contains(self) }
    /// Photos or videos only. Timeline pages switch to the search API for it, which can't search a partner's library.
    /// Assign Location stays on the timeline API, whose coordinates its location filter needs.
    var offersMediaTypeFilter: Bool { ![.videos, .partner, .geolocation].contains(self) }
    /// Assign Location: only the items the map leaves out, those without GPS coordinates.
    var offersLocationFilter: Bool { self == .geolocation }
    /// The page is for finding items without a location, so it starts with only those.
    var defaultLocation: GridLocation { offersLocationFilter ? .missing : .all }
    /// Date Added orders the timeline only; search has no upload-date order.
    var offersSortBy: Bool { ![.videos, .largeFiles].contains(self) }
    /// Large Files is always largest first.
    var offersOrder: Bool { self != .largeFiles }

    func key(_ setting: String) -> String { "grid.\(rawValue).\(setting)" }
}

enum GridShow: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites"
    var id: Self { self }
    var title: LocalizedStringResource { self == .all ? "All Items" : "Favorites" }
}

enum GridMediaType: String, CaseIterable, Identifiable {
    // Immich's AssetType values, and all.
    case all = "ALL", photos = "IMAGE", videos = "VIDEO"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "Photos and Videos"
        case .photos: "Photos"
        case .videos: "Videos"
        }
    }
}

enum GridLocation: String, CaseIterable, Identifiable {
    case missing = "Missing", all = "All"
    var id: Self { self }
    var title: LocalizedStringResource { self == .missing ? "Without Location" : "All Items" }
}

enum GridSortBy: String, CaseIterable, Identifiable {
    // Immich's AssetOrderBy values.
    case dateTaken = "takenAt", dateAdded = "createdAt"
    var id: Self { self }
    var title: LocalizedStringResource { self == .dateTaken ? "Date Taken" : "Date Added" }
}

enum GridOrder: String, CaseIterable, Identifiable {
    case newestFirst = "desc", oldestFirst = "asc"
    var id: Self { self }
    var title: LocalizedStringResource { self == .newestFirst ? "Newest First" : "Oldest First" }
}

struct GridArrangement: Equatable {
    var show = GridShow.all
    var mediaType = GridMediaType.all
    var sortBy = GridSortBy.dateTaken
    var order = GridOrder.newestFirst
    var location = GridLocation.all

    init(show: GridShow = .all, mediaType: GridMediaType = .all, sortBy: GridSortBy = .dateTaken, order: GridOrder = .newestFirst,
         location: GridLocation = .all) {
        self.show = show
        self.mediaType = mediaType
        self.sortBy = sortBy
        self.order = order
        self.location = location
    }

    /// The settings a page saved with `@AppStorage`, limited to the options it offers.
    init(page: GridPage, defaults: UserDefaults = .standard) {
        let value = { (setting: String) in defaults.string(forKey: page.key(setting)) }
        show = page.offersFavoritesFilter ? value("show").flatMap(GridShow.init) ?? .all : .all
        mediaType = page.offersMediaTypeFilter ? value("mediaType").flatMap(GridMediaType.init) ?? .all : .all
        sortBy = page.offersSortBy ? value("sortBy").flatMap(GridSortBy.init) ?? .dateTaken : .dateTaken
        order = page.offersOrder ? value("order").flatMap(GridOrder.init) ?? .newestFirst : .newestFirst
        location = page.offersLocationFilter ? value("location").flatMap(GridLocation.init) ?? page.defaultLocation : .all
    }

    var isFiltered: Bool { show != .all || mediaType != .all || location != .all }

    /// Assign Location: the timeline API can't filter by location, so the grid drops located items itself.
    /// Like Immich's map, an item has a location when it has both a latitude and a longitude.
    var hidesLocated: Bool { location == .missing }

    /// The favorites filter for the search API, which leaves it out when not filtering.
    var isFavorite: Bool? { show == .favorites ? true : nil }

    /// The asset type for the search API (Immich's AssetType), if filtering by one.
    var assetType: String? { mediaType == .all ? nil : mediaType.rawValue }

    /// Date Added needs `orderBy` on the timeline API, new in Immich v3.0. Older servers keep Date Taken.
    static func supportsDateAdded(_ version: ServerVersion?) -> Bool { (version?.major ?? 0) >= 3 }

    /// Timeline pages show photos or videos only through the search API, since the timeline API has no
    /// type filter. Search groups into months by date taken and leaves out partners' photos.
    var searchesTimeline: Bool { mediaType != .all }

    /// Sorting by Date Added: on servers with it, and not while searching, which has no upload-date order.
    func sortsByDateAdded(_ dateAdded: Bool) -> Bool { dateAdded && sortBy == .dateAdded && !searchesTimeline }

    func applied(to query: TimelineQuery, dateAdded: Bool) -> TimelineQuery {
        var query = query
        if show == .favorites {
            query.isFavorite = true
            // The server refuses partners' photos together with a favorites filter.
            query.withPartners = nil
        }
        if order == .oldestFirst { query.order = order.rawValue }
        if sortsByDateAdded(dateAdded) { query.orderBy = sortBy.rawValue }
        return query
    }

    /// The month an asset falls in, as the first seven characters of a bucket ID ("2026-11").
    /// Date Added buckets go by the upload time in UTC, Date Taken buckets by the photo's own clock.
    func month(localDateTime: String, createdAt: String?, dateAdded: Bool) -> Substring? {
        guard sortsByDateAdded(dateAdded) else { return localDateTime.prefix(7) }
        return createdAt.flatMap(ImmichDate.parse).map { Self.utcMonth.string(from: $0).prefix(7) }
    }

    private static let utcMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}
