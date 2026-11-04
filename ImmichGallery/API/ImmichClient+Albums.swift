import Foundation

extension ImmichClient {
    func albumCollections(legacy: Bool) async throws -> [Album] {
        let all = try await albums()
        guard legacy else { return all }
        let shared: [Album]
        do { shared = try await sharedAlbums(legacy: legacy) }
        catch ImmichError.http(404, _) { shared = [] }
        return Array(Dictionary((all + shared).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values)
    }

    func albumDetails(_ id: String) async throws -> AlbumDetails { try await get("albums/\(id)") }

    func sharedAlbums(legacy: Bool) async throws -> [Album] {
        try await get("albums", query: [legacy ? "shared" : "isShared": "true"])
    }

    func createAlbum(name: String, description: String? = nil, assetIDs: [String]) async throws -> AlbumDetails {
        struct Body: Encodable { let albumName: String; let description: String?; let assetIds: [String] }
        return try await send("POST", "albums", body: Body(albumName: name, description: description == "" ? nil : description, assetIds: assetIDs))
    }

    func updateAlbum(_ id: String, _ update: AlbumUpdate) async throws -> AlbumDetails {
        try await send("PATCH", "albums/\(id)", body: update)
    }

    func deleteAlbum(_ id: String) async throws { try await send("DELETE", "albums/\(id)") }

    func changeAlbumAssets(_ id: String, ids: [String], removing: Bool = false) async throws {
        struct Body: Encodable { let ids: [String] }
        let results: [AlbumAssetResult] = try await send(removing ? "DELETE" : "PUT", "albums/\(id)/assets", body: Body(ids: ids))
        let failures = results.filter { !$0.success && $0.error != "duplicate" }
        if !failures.isEmpty {
            throw ImmichError.http(400, "\(failures.count) items could not be \(removing ? "removed" : "added"): \(failures.compactMap(\.error).joined(separator: ", ")).")
        }
    }

    func albumUsers() async throws -> [User] { try await get("users") }

    func addAlbumUser(_ id: String, userID: String, role: String) async throws {
        struct Member: Encodable { let userId: String; let role: String }
        struct Body: Encodable { let albumUsers: [Member] }
        try await send("PUT", "albums/\(id)/users", body: Body(albumUsers: [Member(userId: userID, role: role)]))
    }

    func updateAlbumUser(_ id: String, userID: String, role: String) async throws {
        struct Body: Encodable { let role: String }
        try await send("PUT", "albums/\(id)/user/\(userID)", body: Body(role: role))
    }

    func removeAlbumUser(_ id: String, userID: String) async throws {
        try await send("DELETE", "albums/\(id)/user/\(userID)")
    }

    func albumActivities(_ id: String, assetID: String?) async throws -> [AlbumActivity] {
        try await get("activities", query: ["albumId": id, "assetId": assetID])
    }

    func albumActivityStatistics(_ id: String, assetID: String?) async throws -> AlbumActivityStatistics {
        try await get("activities/statistics", query: ["albumId": id, "assetId": assetID])
    }

    func createAlbumActivity(_ id: String, assetID: String?, comment: String?) async throws -> AlbumActivity {
        struct Body: Encodable { let albumId: String; let assetId: String?; let type: String; let comment: String? }
        return try await send("POST", "activities", body: Body(albumId: id, assetId: assetID, type: comment == nil ? "like" : "comment", comment: comment))
    }

    func deleteAlbumActivity(_ id: String) async throws { try await send("DELETE", "activities/\(id)") }

    func albumTimeBuckets(_ query: TimelineQuery, order: String) async throws -> [TimeBucket] {
        var parameters = query.parameters
        parameters["order"] = order
        return try await get("timeline/buckets", query: parameters)
    }

    func albumTimeBucket(_ bucket: String, _ query: TimelineQuery, order: String) async throws -> TimeBucketAssets {
        var parameters = query.parameters
        parameters["order"] = order
        parameters["timeBucket"] = bucket
        return try await get("timeline/bucket", query: parameters)
    }
}
