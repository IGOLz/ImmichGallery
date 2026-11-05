import Foundation

/// What the app prepares for the desktop widgets, kept in the shared App Group container:
/// downscaled photos for each source a widget shows, the albums, people and places to choose
/// from, and library statistics. The widgets only read these files: they never contact the
/// server and never see a credential.
enum WidgetFeed {
    // One widget per source, so the gallery lists them all. "FeaturedPhotos" is the 0.3.1 kind.
    static let featuredKind = "FeaturedPhotos"
    static let favoritesKind = "FavoritePhotos"
    static let albumKind = "AlbumPhotos"
    static let personKind = "PersonPhotos"
    static let placeKind = "PlacePhotos"
    static let chosenKind = "ChosenPhotos"
    /// Several photos at once, from any source chosen in its settings.
    static let mosaicKind = "PhotoMosaic"
    static let libraryKind = "LibraryStats"
    static let photoKinds: Set<String> = [featuredKind, favoritesKind, albumKind, personKind, placeKind, chosenKind, mosaicKind]
    #if DEBUG
    static let urlScheme = "immichgallery-dev"
    #else
    static let urlScheme = "immichgallery"
    #endif
    /// How long each photo stays on the widget before the next one.
    static let rotation: TimeInterval = 3600

    // MARK: Sources

    enum Source: Hashable, Sendable {
        case featured, favorites, chosen
        case album(String), person(String), place(String)

        init?(key: String) {
            let (kind, value) = key.firstIndex(of: ":").map { (String(key[..<$0]), String(key[key.index(after: $0)...])) } ?? (key, "")
            switch kind {
            case "featured": self = .featured
            case "favorites": self = .favorites
            case "chosen": self = .chosen
            case "album" where WidgetFeed.isID(value): self = .album(value)
            case "person" where WidgetFeed.isID(value): self = .person(value)
            case "place" where !value.isEmpty: self = .place(value)
            default: return nil
            }
        }

        /// Stable key of the photo pool this source fills.
        var key: String {
            switch self {
            case .featured: "featured"
            case .favorites: "favorites"
            case .chosen: "chosen"
            case .album(let id): "album:" + id
            case .person(let id): "person:" + id
            case .place(let city): "place:" + city
            }
        }
    }

    struct Photo: Codable, Hashable, Sendable {
        var assetID: String
        var memoryID: String?
        var caption: String
        var file: String
    }

    struct Pool: Codable, Sendable {
        var updated: Date
        var photos: [Photo]
    }

    struct Catalog: Codable, Sendable {
        struct Item: Codable, Hashable, Sendable {
            var id: String
            var name: String
        }
        var updated: Date
        var albums: [Item]
        var people: [Item]
        var places: [Item]
    }

    struct Stats: Codable, Sendable {
        var updated: Date
        var photos: Int
        var videos: Int
        var albums: Int
        var people: Int?
        var libraryBytes: Int64?
        var diskUsed: Int64?
        var diskSize: Int64?
    }

    struct Manifest: Codable, Sendable {
        /// Hash of the account the data comes from (never the credential itself).
        var account: String
        var pools: [String: Pool] = [:]
        var catalog: Catalog?
        var stats: Stats?
    }

    // MARK: Files

    /// `<group container>/Widget`. Nil when the App Group is missing from the signature.
    static let directory: URL? = {
        guard let group = appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("Widget", isDirectory: true)
    }()

    static let appGroup: String? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ImmichAppGroup") as? String, !group.isEmpty else { return nil }
        return group
    }()

    static var manifestURL: URL? { directory?.appendingPathComponent("feed.json") }
    static var imagesURL: URL? { directory?.appendingPathComponent("images", isDirectory: true) }

    static func load() -> Manifest? {
        guard let url = manifestURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func fileURL(_ photo: Photo) -> URL? { imagesURL?.appendingPathComponent(photo.file) }

    // MARK: Telling the app

    /// Posted by a widget that has no photos yet, so a running app prepares them right away.
    /// Sandboxed processes may only use Darwin notifications prefixed with their App Group.
    static var needsPhotosNotification: String? { appGroup.map { $0 + ".widget-needs-photos" } }

    static func postNeedsPhotos() {
        guard let name = needsPhotosNotification else { return }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    // MARK: Shared defaults

    private static var defaults: UserDefaults? { appGroup.flatMap { UserDefaults(suiteName: $0) } }

    /// The widgets note which sources they show, so the app prepares exactly those.
    /// (The app can't always resolve an album or person from a widget's configuration itself.)
    static func noteRequested(_ source: Source) {
        guard let defaults else { return }
        var requested = defaults.dictionary(forKey: "requested") as? [String: Double] ?? [:]
        requested[source.key] = Date().timeIntervalSince1970
        defaults.set(requested, forKey: "requested")
    }

    /// Sources a widget asked for within `age`.
    static func requested(within age: TimeInterval) -> [Source] {
        let requested = defaults?.dictionary(forKey: "requested") as? [String: Double] ?? [:]
        let cutoff = Date().timeIntervalSince1970 - age
        return requested.filter { $0.value > cutoff }.keys.sorted().compactMap(Source.init(key:))
    }

    // MARK: Rotation

    /// "Next Photo" clicks per pool, added to the clock-based position.
    static func offset(_ pool: String) -> Int {
        defaults?.integer(forKey: "offset." + pool) ?? 0
    }

    static func advance(_ pool: String) {
        guard let defaults else { return }
        defaults.set(defaults.integer(forKey: "offset." + pool) + 1, forKey: "offset." + pool)
    }

    /// `count` consecutive photos for `date`. Rotation follows the clock, so reloads don't restart it.
    static func photos(at date: Date, in photos: [Photo], count: Int = 1, offset: Int = 0) -> [Photo] {
        guard !photos.isEmpty, count > 0 else { return [] }
        let slot = Int((date.timeIntervalSince1970 / rotation).rounded(.down)) + offset
        let start = slot &* count
        return (0..<min(count, photos.count)).map { i in
            photos[(((start &+ i) % photos.count) + photos.count) % photos.count]
        }
    }

    static func photo(at date: Date, in photos: [Photo], offset: Int = 0) -> Photo? {
        self.photos(at: date, in: photos, offset: offset).first
    }

    // MARK: Links opened by a click on a widget

    enum Link: Equatable, Sendable {
        case open
        case memory(String)
        case photo(String)

        init?(_ url: URL) {
            guard url.scheme == WidgetFeed.urlScheme else { return nil }
            // Any web page can open this scheme: accept only Immich IDs (UUIDs).
            let id = url.pathComponents.dropFirst().first.flatMap { WidgetFeed.isID($0) ? $0 : nil }
            switch url.host() {
            case "memory": guard let id else { return nil }; self = .memory(id)
            case "photo": guard let id else { return nil }; self = .photo(id)
            default: self = .open
            }
        }

        var url: URL {
            switch self {
            case .open: URL(string: "\(WidgetFeed.urlScheme)://open")!
            case .memory(let id): URL(string: "\(WidgetFeed.urlScheme)://memory/\(id)")!
            case .photo(let id): URL(string: "\(WidgetFeed.urlScheme)://photo/\(id)")!
            }
        }
    }

    static func isID(_ text: String) -> Bool { UUID(uuidString: text) != nil }

    /// Every photo, memories included, opens in the app's All Photos at its place in the timeline.
    static func link(for photo: Photo) -> Link { .photo(photo.assetID) }
}
