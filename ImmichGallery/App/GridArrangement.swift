import Foundation

// Grid pages: view options in the style of Apple Photos. Immich's web app has none for these pages, so
// they stay with what the server filters and orders: the timeline API (GET /timeline/buckets) and, for
// Videos and Large Files, the search API.

/// The grid pages with view options. Each saves its own settings.
enum GridPage: String {
    case library, favorites, archive, partner, person, tag, locked
    case videos, largeFiles

    /// A Favorites filter adds nothing on Favorites, and partners' favorites are their own.
    var offersFavoritesFilter: Bool { ![.favorites, .partner].contains(self) }
    /// Large Files mixes photos and videos; every other page is either a timeline or Videos.
    var offersMediaTypeFilter: Bool { self == .largeFiles }
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

    init(show: GridShow = .all, mediaType: GridMediaType = .all, sortBy: GridSortBy = .dateTaken, order: GridOrder = .newestFirst) {
        self.show = show
        self.mediaType = mediaType
        self.sortBy = sortBy
        self.order = order
    }

    /// The settings a page saved with `@AppStorage`, limited to the options it offers.
    init(page: GridPage, defaults: UserDefaults = .standard) {
        let value = { (setting: String) in defaults.string(forKey: page.key(setting)) }
        show = page.offersFavoritesFilter ? value("show").flatMap(GridShow.init) ?? .all : .all
        mediaType = page.offersMediaTypeFilter ? value("mediaType").flatMap(GridMediaType.init) ?? .all : .all
        sortBy = page.offersSortBy ? value("sortBy").flatMap(GridSortBy.init) ?? .dateTaken : .dateTaken
        order = page.offersOrder ? value("order").flatMap(GridOrder.init) ?? .newestFirst : .newestFirst
    }

    var isFiltered: Bool { show != .all || mediaType != .all }

    /// The favorites filter for the search API, which leaves it out when not filtering.
    var isFavorite: Bool? { show == .favorites ? true : nil }

    /// The asset type for the search API (Immich's AssetType), if filtering by one.
    var assetType: String? { mediaType == .all ? nil : mediaType.rawValue }

    /// Date Added needs `orderBy` on the timeline API, new in Immich v3.0. Older servers keep Date Taken.
    static func supportsDateAdded(_ version: ServerVersion?) -> Bool { (version?.major ?? 0) >= 3 }

    func applied(to query: TimelineQuery, dateAdded: Bool) -> TimelineQuery {
        var query = query
        if show == .favorites {
            query.isFavorite = true
            // The server refuses partners' photos together with a favorites filter.
            query.withPartners = nil
        }
        if order == .oldestFirst { query.order = order.rawValue }
        if dateAdded && sortBy == .dateAdded { query.orderBy = sortBy.rawValue }
        return query
    }

    /// The month an asset falls in, as the first seven characters of a bucket ID ("2026-11").
    /// Date Added buckets go by the upload time in UTC, Date Taken buckets by the photo's own clock.
    func month(localDateTime: String, createdAt: String?, dateAdded: Bool) -> Substring? {
        guard dateAdded && sortBy == .dateAdded else { return localDateTime.prefix(7) }
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
