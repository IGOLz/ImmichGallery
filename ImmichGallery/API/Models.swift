import Foundation

// DTOs for the subset of the Immich API this app uses.
// Verified against the official OpenAPI spec (server v3.3.x). Fields that are
// missing on older servers are optional so decoding stays tolerant.

struct ServerVersion: Decodable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }
    var isSupported: Bool { major >= 2 }
}

struct ServerFeatures: Decodable, Sendable {
    var ocr = false
    var duplicateDetection: Bool?
    var smartSearch = false
    var facialRecognition = false
    var map = false
    var trash = true
    var passwordLogin = true
    var oauth = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ocr = try c.decodeIfPresent(Bool.self, forKey: .ocr) ?? false
        duplicateDetection = try c.decodeIfPresent(Bool.self, forKey: .duplicateDetection)
        smartSearch = try c.decodeIfPresent(Bool.self, forKey: .smartSearch) ?? false
        facialRecognition = try c.decodeIfPresent(Bool.self, forKey: .facialRecognition) ?? false
        map = try c.decodeIfPresent(Bool.self, forKey: .map) ?? false
        trash = try c.decodeIfPresent(Bool.self, forKey: .trash) ?? true
        passwordLogin = try c.decodeIfPresent(Bool.self, forKey: .passwordLogin) ?? true
        oauth = try c.decodeIfPresent(Bool.self, forKey: .oauth) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case ocr, duplicateDetection, smartSearch, facialRecognition, map, trash, passwordLogin, oauth
    }
}

struct LoginResponse: Decodable, Sendable {
    let accessToken: String
    let userId: String
    let userEmail: String
    let name: String
}

struct User: Decodable, Sendable, Identifiable {
    let id: String
    let email: String
    let name: String
    var shouldChangePassword: Bool?
    var isAdmin: Bool? // Admin: absent on older servers means no admin access.
    var profileImagePath: String?
    var quotaUsageInBytes: Int64?
    var quotaSizeInBytes: Int64?
}

struct TimeBucket: Decodable, Sendable {
    let timeBucket: String
    let count: Int
}

/// Video duration. Immich ≥ 3.x sends milliseconds as an integer;
/// older servers send a "H:MM:SS.ffffff" string.
struct MediaDuration: Decodable, Sendable, Hashable {
    let milliseconds: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let ms = try? c.decode(Int.self) {
            milliseconds = ms
        } else if let s = try? c.decode(String.self) {
            let parts = s.split(separator: ":").compactMap { Double($0) }
            let seconds = parts.reduce(0) { $0 * 60 + $1 }
            milliseconds = Int(seconds * 1000)
        } else {
            milliseconds = 0
        }
    }
}

/// Columnar response of `GET /timeline/bucket`.
struct TimeBucketAssets: Decodable, Sendable {
    let id: [String]
    let isImage: [Bool]
    let isFavorite: [Bool]
    let isTrashed: [Bool]
    let thumbhash: [String?]
    let ratio: [Double?]
    let duration: [MediaDuration?]
    let fileCreatedAt: [String]
    let livePhotoVideoId: [String?]
    var ownerId: [String]?
    var stack: [[String]?]?
    var city: [String?]?
    var country: [String?]?
}

enum AssetType: String, Decodable, Sendable {
    case image = "IMAGE", video = "VIDEO", audio = "AUDIO", other = "OTHER"
}

struct Exif: Decodable, Sendable {
    var projectionType: String? // Metadata: panoramas cannot be edited.
    var make: String?
    var model: String?
    var lensModel: String?
    var fNumber: Double?
    var focalLength: Double?
    var iso: Int?
    var exposureTime: String?
    var orientation: String? // Metadata: crop coordinates use orientation-corrected original dimensions.
    var exifImageWidth: Int?
    var exifImageHeight: Int?
    var fileSizeInByte: Int64?
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var state: String?
    var country: String?
    var description: String?
    var dateTimeOriginal: String?
    var timeZone: String?
    var rating: Int?
}

struct AssetPerson: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
}

struct AssetResponse: Decodable, Sendable, Identifiable {
    let id: String
    var ownerId: String?
    let type: AssetType
    let originalFileName: String
    var originalMimeType: String?
    let fileCreatedAt: String
    let localDateTime: String
    var isFavorite: Bool
    var isTrashed: Bool
    var visibility: String?
    var duration: MediaDuration?
    var thumbhash: String?
    var livePhotoVideoId: String?
    var width: Int?
    var height: Int?
    var exifInfo: Exif?
    var people: [AssetPerson]?
    var isEdited: Bool? // People: face coordinates include server edits.
    var stack: AssetsStackSummary?
}

struct Album: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let albumName: String
    var albumThumbnailAssetId: String?
    var assetCount: Int
    var shared: Bool
    var description: String?
    var startDate: String?
    var endDate: String?
    var lastModifiedAssetTimestamp: String?
    var updatedAt: String?

    var albumUsers: [AlbumMember]?
    var owner: User?
    var ownerId: String?

    func canEdit(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return (owner?.id ?? ownerId) == userID
            || albumUsers?.contains(where: { $0.id == userID && ["owner", "editor"].contains($0.role) }) == true
    }

    static func == (a: Album, b: Album) -> Bool {
        a.id == b.id && a.albumName == b.albumName && a.assetCount == b.assetCount
            && a.albumThumbnailAssetId == b.albumThumbnailAssetId
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Person: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    var isHidden: Bool
    var isFavorite: Bool?
    var birthDate: String? // People
}

struct PeopleResponse: Decodable, Sendable {
    let people: [Person]
    let total: Int
    var hasNextPage: Bool?
}

struct SearchResponse: Decodable, Sendable {
    struct Assets: Decodable, Sendable {
        let items: [AssetResponse]
        var nextPage: String?
        var nextCursor: String?
    }
    let assets: Assets
}
