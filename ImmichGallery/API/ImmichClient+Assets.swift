import Foundation

extension ImmichClient {
    func assetsCreateStack(_ ids: [String]) async throws -> AssetsStack {
        struct Body: Encodable { let assetIds: [String] }
        return try await send("POST", "stacks", body: Body(assetIds: ids))
    }

    func assetsStack(_ id: String) async throws -> AssetsStack { try await get("stacks/\(id)") }

    func assetsSetPrimary(stack: String, asset: String) async throws -> AssetsStack {
        struct Body: Encodable { let primaryAssetId: String }
        return try await send("PUT", "stacks/\(stack)", body: Body(primaryAssetId: asset))
    }

    func assetsUnstack(_ id: String) async throws { try await send("DELETE", "stacks/\(id)") }
    func assetsRemoveFromStack(_ id: String, asset: String) async throws {
        try await send("DELETE", "stacks/\(id)/assets/\(asset)")
    }

    func assetsDuplicates() async throws -> [AssetsDuplicate] { try await get("duplicates") }
    func assetsDismissDuplicate(_ id: String) async throws { try await send("DELETE", "duplicates/\(id)") }
    func assetsResolveDuplicate(_ group: AssetsDuplicate, keep: Set<String>) async throws {
        struct Group: Encodable { let duplicateId: String; let keepAssetIds: [String]; let trashAssetIds: [String] }
        struct Body: Encodable { let groups: [Group] }
        let results: [AssetsBulkResult] = try await send("POST", "duplicates/resolve", body: Body(groups: [
            Group(duplicateId: group.id, keepAssetIds: group.assets.map(\.id).filter { keep.contains($0) },
                  trashAssetIds: group.assets.map(\.id).filter { !keep.contains($0) })
        ]))
        if results.contains(where: { !$0.success }) { throw ImmichError.http(409, String(localized: "The duplicate group could not be resolved. Reload and try again.")) }
    }

    // Deprecated since v3.2.0 in favor of searchAssets; retained for the v3.3.5 web utility contract.
    /// `type` is Immich's AssetType ("IMAGE" or "VIDEO").
    func assetsLargeFiles(type: String? = nil, isFavorite: Bool? = nil) async throws -> [AssetResponse] {
        let data = try await data(for: request("search/large-assets", method: "POST",
                                               query: ["minFileSize": "0", "type": type, "isFavorite": isFavorite.map(String.init)]))
        return try JSONDecoder().decode([AssetResponse].self, from: data)
    }

    func assetsSetLocation(_ ids: [String], latitude: Double, longitude: Double) async throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ImmichError.http(400, String(localized: "Enter latitude from -90 to 90 and longitude from -180 to 180."))
        }
        struct Body: Encodable { let ids: [String]; let latitude: Double; let longitude: Double }
        try await send("PUT", "assets", body: Body(ids: ids, latitude: latitude, longitude: longitude))
    }

    func assetsDownloadInfo(ids: [String]?, album: String?, archiveSize: Int64?) async throws -> AssetsDownloadInfo {
        struct Body: Encodable { let assetIds: [String]?; let albumId: String?; let archiveSize: Int64? }
        return try await send("POST", "download/info", body: Body(assetIds: ids, albumId: album, archiveSize: archiveSize))
    }

    func assetsArchiveRequest(_ ids: [String], archiveName: String) throws -> URLRequest {
        struct Body: Encodable { let assetIds: [String]; let archiveName: String }
        return try request("download/archive", method: "POST", body: Body(assetIds: ids, archiveName: archiveName))
    }
}
