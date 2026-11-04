import Foundation

struct ExplorePreferences: Decodable, Sendable {
    struct Feature: Decodable, Sendable { let enabled: Bool; var duration: Int? }
    var memories: Feature?
    var tags: Feature?
    var folders: Feature?
}

struct ExploreMarker: Decodable, Identifiable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
    var city: String?
}

struct ExploreTag: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let value: String
    var color: String?
    var parentId: String?
}

struct ExploreMemory: Decodable, Identifiable, Sendable {
    struct Details: Decodable, Sendable { let year: Int; var personName: String? }
    let id: String
    let type: String
    let data: Details
    var assets: [AssetResponse]
    var seenAt: String?
    var title: String { type == "birthday" ? "\(data.personName ?? "Birthday") • \(data.year)" : "On This Day • \(data.year)" }
}

struct ExploreAuthStatus: Decodable, Sendable {
    let pinCode: Bool
    let isElevated: Bool
    let password: Bool
}

struct ExploreIDs: Encodable { let ids: [String] }
struct ExploreBulkResult: Decodable { let id: String; let success: Bool; var error: String? }

enum ExploreSource: Hashable, Sendable {
    case city(String), tag(String), folder(String), markers([String])
}
