import Foundation

extension ImmichClient {
    func explorePreferences() async throws -> ExplorePreferences { try await get("users/me/preferences") }
    func exploreTags() async throws -> [ExploreTag] { try await get("tags") }
    func exploreCities() async throws -> [AssetResponse] { try await get("search/cities") }
    func explorePaths() async throws -> [String] { try await get("view/folder/unique-paths") }
    func exploreMarkers(favorites: Bool, archived: Bool, partners: Bool, after: Date?, before: Date?) async throws -> [ExploreMarker] {
        try await get("map/markers", query: ["isFavorite": favorites ? "true" : nil,
            "isArchived": archived ? "true" : nil, "withPartners": String(partners),
            "fileCreatedAfter": after.map { $0.ISO8601Format() }, "fileCreatedBefore": before.map { $0.ISO8601Format() }])
    }
    func exploreAssets(_ source: ExploreSource, page: SearchPage) async throws -> SearchResponse.Assets {
        switch source {
        case .folder(let path):
            let assets: [AssetResponse] = try await get("view/folder", query: ["path": path])
            return .init(items: assets.filter { $0.visibility != "locked" })
        case .city(let city):
            struct Body: Encodable { let city: String; var page: Int?; var cursor: String?; let size = 250; let visibility = "timeline" }
            let response: SearchResponse = try await send("POST", "search/metadata", body: Body(city: city, page: page.page, cursor: page.cursor))
            return response.assets
        case .tag, .map: return .init(items: []) // Tags use the timeline endpoint.
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
        if result.contains(where: { !$0.isAccepted(removing: remove) }) { throw ImmichError.http(400, "Some items could not be updated. Refresh and try again.") }
    }
    func exploreMemories(page: Int) async throws -> [ExploreMemory] {
        try await get("memories", query: ["for": String(Date().ISO8601Format().prefix(10)), "page": String(page), "size": "100", "isTrashed": "false", "isUpcoming": "false"])
    }
    func exploreSeenMemory(_ id: String) async throws {
        struct Body: Encodable { let seenAt: String }
        let _: ExploreMemory = try await send("PUT", "memories/\(id)", body: Body(seenAt: Date().ISO8601Format()))
    }
    func exploreDeleteMemory(_ id: String) async throws { try await send("DELETE", "memories/\(id)") }
    func exploreRemoveMemoryAsset(_ memory: String, asset: String) async throws {
        let result: [ExploreBulkResult] = try await send("DELETE", "memories/\(memory)/assets", body: ExploreIDs(ids: [asset]))
        guard result.allSatisfy(\.success) else { throw ImmichError.http(400, "The photo could not be removed from this memory.") }
    }
    func exploreAuth() async throws -> ExploreAuthStatus { try await get("auth/status") }
    func exploreUnlock(_ pin: String, setup: Bool) async throws {
        guard exploreSupportsLockedFolder else { throw ImmichError.http(400, "Locked Folder requires a session-token login.") }
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
    var exploreSupportsLockedFolder: Bool {
        if case .accessToken = credential { return true }
        return false
    }
    func explorePrivateClient() -> ImmichClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: URLSession(configuration: configuration))
    }
}
