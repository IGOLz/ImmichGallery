import Foundation

// Timeline pages: view options in the style of Apple Photos. Immich's web timeline has none, so these
// stay with what the timeline API filters and orders on the server (GET /timeline/buckets).

/// The timeline pages with view options. Each saves its own settings.
enum TimelinePage: String {
    case library, favorites, archive, partner, person, tag, locked

    /// A Favorites filter adds nothing on Favorites, and partners' favorites are their own.
    var offersFavoritesFilter: Bool { self != .favorites && self != .partner }

    func key(_ setting: String) -> String { "timeline.\(rawValue).\(setting)" }
}

enum TimelineShow: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites"
    var id: Self { self }
    var title: LocalizedStringResource { self == .all ? "All Items" : "Favorites" }
}

enum TimelineSortBy: String, CaseIterable, Identifiable {
    // Immich's AssetOrderBy values.
    case dateTaken = "takenAt", dateAdded = "createdAt"
    var id: Self { self }
    var title: LocalizedStringResource { self == .dateTaken ? "Date Taken" : "Date Added" }
}

enum TimelineOrder: String, CaseIterable, Identifiable {
    case newestFirst = "desc", oldestFirst = "asc"
    var id: Self { self }
    var title: LocalizedStringResource { self == .newestFirst ? "Newest First" : "Oldest First" }
}

struct TimelineArrangement: Equatable {
    var show = TimelineShow.all
    var sortBy = TimelineSortBy.dateTaken
    var order = TimelineOrder.newestFirst

    init(show: TimelineShow = .all, sortBy: TimelineSortBy = .dateTaken, order: TimelineOrder = .newestFirst) {
        self.show = show
        self.sortBy = sortBy
        self.order = order
    }

    /// The settings a page saved with `@AppStorage`.
    init(page: TimelinePage, defaults: UserDefaults = .standard) {
        let value = { (setting: String) in defaults.string(forKey: page.key(setting)) }
        show = page.offersFavoritesFilter ? value("show").flatMap(TimelineShow.init) ?? .all : .all
        sortBy = value("sortBy").flatMap(TimelineSortBy.init) ?? .dateTaken
        order = value("order").flatMap(TimelineOrder.init) ?? .newestFirst
    }

    var isFiltered: Bool { show != .all }

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
