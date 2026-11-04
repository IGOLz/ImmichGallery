import Foundation

struct AccountAPIKey: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let permissions: [String]
    let createdAt: String?
}

struct AccountAPIKeySecret: Decodable, Sendable {
    let secret: String
    let apiKey: AccountAPIKey?
    let id: String?
}

struct AccountDevice: Decodable, Identifiable, Sendable {
    let id: String
    let current: Bool
    let deviceOS: String
    let deviceType: String
    let appVersion: String?
    let updatedAt: String
}

struct AccountNotification: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let level: String
    let createdAt: String
    let readAt: String?
}

/// Optional groups preserve compatibility with servers predating individual preferences.
struct AccountPreferences: Codable, Sendable {
    struct Feature: Codable, Sendable {
        var enabled: Bool?
        var sidebarWeb: Bool?
        var duration: Int?
        var minimumFaces: Int?
        var updateStrategy: String?
    }
    struct Download: Codable, Sendable {
        var archiveSize: Int64?
        var includeEmbeddedVideos: Bool?
    }
    struct Email: Codable, Sendable {
        var enabled: Bool?
        var albumInvite: Bool?
        var albumUpdate: Bool?
    }
    struct Albums: Codable, Sendable { var defaultAssetOrder: String? }
    struct Cast: Codable, Sendable { var gCastEnabled: Bool? }
    struct RecentlyAdded: Codable, Sendable { var sidebarWeb: Bool? }
    struct Purchase: Codable, Sendable { var showSupportBadge: Bool?; var hideBuyButtonUntil: String? }
    var memories: Feature?
    var ratings: Feature?
    var folders: Feature?
    var tags: Feature?
    var people: Feature?
    var sharedLinks: Feature?
    var download: Download?
    var emailNotifications: Email?
    var albums: Albums?
    var cast: Cast?
    var recentlyAdded: RecentlyAdded?
    var purchase: Purchase?
}
