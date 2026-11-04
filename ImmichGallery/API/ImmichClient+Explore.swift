import Foundation

extension ImmichClient {
    func explorePreferences() async throws -> ExplorePreferences { try await get("users/me/preferences") }
    func exploreTags() async throws -> [ExploreTag] { try await get("tags") }
    func exploreCities() async throws -> [AssetResponse] { try await get("search/cities") }
    func explorePaths() async throws -> [String] { try await get("view/folder/unique-paths") }
    func exploreMarkers(favorites: Bool, archived: Bool, partners: Bool, after: Date?, before: Date?) async throws -> [ExploreMarker] {
        try await get("map/markers", query: ["isFavorite": favorites ? "true" : nil,
            "isArchived": archived ? nil : "false", "withPartners": String(partners),
            "fileCreatedAfter": after.map { $0.ISO8601Format() }, "fileCreatedBefore": before.map { $0.ISO8601Format() }])
    }
    func exploreAssets(_ source: ExploreSource, page: SearchPage) async throws -> SearchResponse.Assets {
        switch source {
        case .folder(let path):
            let assets: [AssetResponse] = try await get("view/folder", query: ["path": path])
            return .init(items: assets.filter { $0.visibility != "locked" })
        case .markers(let ids):
            let start = ((page.page ?? 1) - 1) * 100
            var assets: [AssetResponse] = []
            // Bounded concurrency avoids one task/request per marker on large clusters.
            for batch in stride(from: start, to: min(start + 100, ids.count), by: 8) {
                let end = min(batch + 8, min(start + 100, ids.count))
                let fetched = try await withThrowingTaskGroup(of: AssetResponse.self) { group in
                    for id in ids[batch..<end] { group.addTask { try await self.asset(id) } }
                    var result: [AssetResponse] = []
                    for try await asset in group { if asset.visibility != "locked" { result.append(asset) } }
                    return result
                }
                assets.append(contentsOf: fetched)
            }
            return .init(items: assets.sorted { $0.localDateTime > $1.localDateTime }, nextPage: start + 100 < ids.count ? String((page.page ?? 1) + 1) : nil)
        case .city(let city):
            struct Body: Encodable { let city: String; var page: Int?; var cursor: String?; let size = 250; let visibility = "timeline" }
            let response: SearchResponse = try await send("POST", "search/metadata", body: Body(city: city, page: page.page, cursor: page.cursor))
            return response.assets
        case .tag: return .init(items: []) // Tags use the timeline endpoint.
        }
    }
    func exploreCreateTag(_ path: String) async throws {
        struct Body: Encodable { let tags: [String] }
        let _: [ExploreTag] = try await send("PUT", "tags", body: Body(tags: [path]))
    }
    func exploreUpdateTag(_ tag: ExploreTag, name: String, color: String) async throws {
        struct Body: Encodable {
            let name: String
            let color: String?
            enum CodingKeys: String, CodingKey { case name, color }
            func encode(to encoder: Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                try values.encode(name, forKey: .name)
                try values.encode(color, forKey: .color)
            }
        }
        let _: ExploreTag = try await send("PUT", "tags/\(tag.id)", body: Body(name: name, color: color.isEmpty ? nil : color))
    }
    func exploreDeleteTag(_ id: String) async throws { try await send("DELETE", "tags/\(id)") }
    func exploreTagAssets(_ ids: [String], tag: String, remove: Bool) async throws {
        let result: [ExploreBulkResult] = try await send(remove ? "DELETE" : "PUT", "tags/\(tag)/assets", body: ExploreIDs(ids: ids))
        if result.contains(where: { !$0.success }) { throw ImmichError.http(400, "Some items could not be updated. Refresh and try again.") }
    }
    func exploreMemories(page: Int) async throws -> [ExploreMemory] {
        try await get("memories", query: ["page": String(page), "size": "100", "isTrashed": "false", "isUpcoming": "false"])
    }
    func exploreSeenMemory(_ id: String) async throws {
        struct Body: Encodable { let seenAt: String }
        let _: ExploreMemory = try await send("PUT", "memories/\(id)", body: Body(seenAt: Date().ISO8601Format()))
    }
    func exploreHideMemory(_ id: String) async throws { try await send("DELETE", "memories/\(id)") }
    func exploreRemoveMemoryAsset(_ memory: String, asset: String) async throws {
        let result: [ExploreBulkResult] = try await send("DELETE", "memories/\(memory)/assets", body: ExploreIDs(ids: [asset]))
        guard result.allSatisfy(\.success) else { throw ImmichError.http(400, "The photo could not be removed from this memory.") }
    }
    func exploreAuth() async throws -> ExploreAuthStatus { try await get("auth/status") }
    func exploreUnlock(_ pin: String, setup: Bool) async throws {
        struct Body: Encodable { let pinCode: String }
        if setup { try await send("POST", "auth/pin-code", body: Body(pinCode: pin)) }
        try await send("POST", "auth/session/unlock", body: Body(pinCode: pin))
    }
    func exploreLock() async throws { try await send("POST", "auth/session/lock") }
    func exploreLocked(page: Int) async throws -> SearchResponse.Assets {
        struct Body: Encodable { let visibility = "locked"; let page: Int; let size = 250 }
        let response: SearchResponse = try await send("POST", "search/metadata", body: Body(page: page))
        return response.assets
    }
    func explorePrivateClient() -> ImmichClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: URLSession(configuration: configuration))
    }
}
