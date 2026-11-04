import Foundation

struct SharedLink: Decodable, Identifiable, Sendable {
    let id: String
    let key: String
    let type: String
    var slug: String?
    var description: String?
    var expiresAt: String?
    var password: String?
    var allowDownload: Bool
    var allowUpload: Bool
    var showMetadata: Bool
    var assets: [AssetResponse]
    var album: Album?

    var title: String { description.flatMap { $0.isEmpty ? nil : $0 } ?? album?.albumName ?? "Shared Photos" }
}

struct SharingPartner: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    var inTimeline: Bool?
}

struct SharingOptions: Encodable {
    var description = ""
    var slug = ""
    var password = ""
    var allowDownload = true
    var allowUpload = false
    var showMetadata = true
    var expiresAt: String?
    var keepPassword = false
    // Null explicitly removes expiry, password and slug when editing.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(description, forKey: .description)
        try c.encode(slug.isEmpty ? nil : slug, forKey: .slug)
        if !keepPassword { try c.encode(password.isEmpty ? nil : password, forKey: .password) }
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(allowDownload, forKey: .allowDownload)
        try c.encode(allowUpload, forKey: .allowUpload)
        try c.encode(showMetadata, forKey: .showMetadata)
    }
    enum CodingKeys: String, CodingKey { case description, slug, password, allowDownload, allowUpload, showMetadata, expiresAt }
}

struct SharingAssetResult: Decodable {
    let assetId: String
    let success: Bool
    var error: String?
}
