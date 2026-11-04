import Foundation

struct MetadataUpdate: Encodable, Sendable {
    var ids: [String]
    var dateTimeOriginal: String?
    var dateTimeRelative: Int?
    var timeZone: String?
    var latitude: Double?
    var longitude: Double?
    var description: String?
    var rating: Int?
    var clearRating = false

    enum CodingKeys: String, CodingKey {
        case ids, dateTimeOriginal, dateTimeRelative, timeZone, latitude, longitude, description, rating
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
        try c.encodeIfPresent(dateTimeOriginal, forKey: .dateTimeOriginal)
        try c.encodeIfPresent(dateTimeRelative, forKey: .dateTimeRelative)
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encodeIfPresent(description, forKey: .description)
        if clearRating { try c.encodeNil(forKey: .rating) }
        else { try c.encodeIfPresent(rating, forKey: .rating) }
    }
}

struct MetadataPreferences: Decodable {
    struct Ratings: Decodable { var enabled: Bool }
    var ratings: Ratings?
}

struct MetadataEdit: Codable, Sendable, Equatable {
    var action: String
    var parameters: Parameters

    struct Parameters: Codable, Sendable, Equatable {
        var angle: Int?
        var axis: String?
        var x: Int?
        var y: Int?
        var width: Int?
        var height: Int?
    }
}

struct MetadataEdits: Codable, Sendable {
    var edits: [MetadataEdit]
}


extension Exif {
    var metadataDimensions: (width: Int, height: Int)? {
        guard let width = exifImageWidth, let height = exifImageHeight, width > 0, height > 0 else { return nil }
        return ["5", "6", "7", "8"].contains(orientation ?? "") ? (height, width) : (width, height)
    }
}

extension AssetResponse {
    func canEditMetadataImage(userID: String?) -> Bool {
        guard let userID, ownerId == userID, type == .image, livePhotoVideoId == nil,
              exifInfo?.projectionType != "EQUIRECTANGULAR", exifInfo?.metadataDimensions != nil else { return false }
        let name = originalFileName.lowercased()
        return ![".gif", ".svg", ".insp"].contains(where: name.hasSuffix)
            && !["image/gif", "image/svg+xml"].contains(originalMimeType?.lowercased() ?? "")
    }
}

extension ServerVersion {
    var supportsMetadataEdits: Bool { (major, minor, patch) >= (2, 5, 0) }
}

/// MapKit can return wrapped longitudes outside the server's accepted range.
func metadataCoordinate(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
    let wrapped = (longitude + 180).truncatingRemainder(dividingBy: 360)
    return (min(90, max(-90, latitude)), (wrapped < 0 ? wrapped + 360 : wrapped) - 180)
}
