import Foundation

/// Photos the app prepares for the desktop widget, kept in the shared App Group container.
/// The widget only reads these files: it never contacts the server and never sees a credential.
enum WidgetFeed {
    static let kind = "FeaturedPhotos"
    static let urlScheme = "immichgallery"
    /// How long each photo stays on the widget before the next one.
    static let rotation: TimeInterval = 3600

    struct Photo: Codable, Hashable, Sendable {
        var assetID: String
        var memoryID: String?
        var caption: String
        var file: String
    }

    struct Manifest: Codable, Sendable {
        /// Hash of the account the photos come from (never the credential itself).
        var account: String
        var updated: Date
        var photos: [Photo]
    }

    /// `<group container>/Widget`. Nil when the App Group is missing from the signature.
    static let directory: URL? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ImmichAppGroup") as? String, !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("Widget", isDirectory: true)
    }()

    static var manifestURL: URL? { directory?.appendingPathComponent("manifest.json") }

    static func load() -> Manifest? {
        guard let url = manifestURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func fileURL(_ photo: Photo) -> URL? { directory?.appendingPathComponent(photo.file) }

    /// The photo shown at `date`. Rotation follows the clock, so reloads don't restart it.
    static func photo(at date: Date, in photos: [Photo]) -> Photo? {
        guard !photos.isEmpty else { return nil }
        let slot = Int((date.timeIntervalSince1970 / rotation).rounded(.down))
        return photos[((slot % photos.count) + photos.count) % photos.count]
    }

    // MARK: Links opened by a click on the widget

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

    static func link(for photo: Photo) -> Link {
        photo.memoryID.map(Link.memory) ?? .photo(photo.assetID)
    }
}
