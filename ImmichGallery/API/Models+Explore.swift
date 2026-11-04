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
    var title: String {
        if type == "birthday" { return "\(data.personName ?? "Birthday") • \(data.year)" }
        let years = max(0, Calendar.current.component(.year, from: Date()) - data.year)
        return years == 1 ? String(localized: "1 year ago") : String(localized: "\(years) years ago")
    }
}

struct ExploreAuthStatus: Decodable, Sendable {
    let pinCode: Bool
    let isElevated: Bool
    let password: Bool
    var pinExpiresAt: String?
}

struct ExploreIDs: Encodable { let ids: [String] }
struct ExploreBulkResult: Decodable {
    let id: String
    let success: Bool
    var error: String?
    func isAccepted(removing: Bool) -> Bool { success || error == (removing ? "not_found" : "duplicate") }
}

enum ExploreSource: Hashable, Sendable {
    case city(String), tag(String), folder(String), map(ExploreMapQuery)
}

struct ExploreMapQuery: Hashable, Sendable {
    let bbox: String
    let favorites: Bool
    let archived: Bool
    let partners: Bool
    let after: Date?
    let before: Date?
    var timeline: TimelineQuery {
        // Immich rejects withPartners together with the favorite or archive filters.
        TimelineQuery(visibility: archived ? nil : "timeline", isFavorite: favorites ? true : nil,
                      withPartners: favorites || archived ? nil : partners, withStacked: false, bbox: bbox)
    }
    func includesMonth(start: Date?) -> Bool {
        guard after != nil || before != nil else { return true }
        guard let start else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return true }
        return (after == nil || end > after!) && (before == nil || start < before!)
    }
    func includes(_ date: Date?) -> Bool {
        guard after != nil || before != nil else { return true }
        guard let date else { return false }
        return (after == nil || date >= after!) && (before == nil || date < before!)
    }
}

struct ExploreTagNode: Identifiable {
    var id: String { tag.id }
    let tag: ExploreTag
    var children: [ExploreTagNode]?
    static func tree(_ tags: [ExploreTag]) -> [ExploreTagNode] {
        let ids = Set(tags.map(\.id))
        let byParent = Dictionary(grouping: tags) { tag in tag.parentId.flatMap { ids.contains($0) ? $0 : nil } ?? "" }
        func nodes(_ parent: String, ancestors: Set<String>) -> [ExploreTagNode] {
            (byParent[parent] ?? []).filter { !ancestors.contains($0.id) }.map { tag in
                let children = nodes(tag.id, ancestors: ancestors.union([tag.id]))
                return ExploreTagNode(tag: tag, children: children.isEmpty ? nil : children)
            }
        }
        return nodes("", ancestors: [])
    }
}
