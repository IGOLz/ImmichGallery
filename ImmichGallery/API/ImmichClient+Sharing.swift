import Foundation

extension ImmichClient {
    func sharedLinks() async throws -> [SharedLink] { try await get("shared-links") }
    func sharedLink(_ id: String) async throws -> SharedLink { try await get("shared-links/\(id)") }

    func createSharedLink(albumID: String?, assetIDs: [String], options: SharingOptions) async throws -> SharedLink {
        struct Body: Encodable {
            let type: String
            let albumId: String?
            let assetIds: [String]?
            let options: SharingOptions
            func encode(to encoder: Encoder) throws {
                try options.encode(to: encoder)
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(type, forKey: .type)
                try c.encodeIfPresent(albumId, forKey: .albumId)
                try c.encodeIfPresent(assetIds, forKey: .assetIds)
            }
            enum Keys: String, CodingKey { case type, albumId, assetIds }
        }
        return try await send("POST", "shared-links", body: Body(type: albumID == nil ? "INDIVIDUAL" : "ALBUM", albumId: albumID, assetIds: albumID == nil ? assetIDs : nil, options: options))
    }
    func editSharedLink(_ id: String, options: SharingOptions, keepPassword: Bool = false) async throws -> SharedLink {
        var options = options
        options.keepPassword = keepPassword
        return try await send("PATCH", "shared-links/\(id)", body: options)
    }
    func deleteSharedLink(_ id: String) async throws { try await send("DELETE", "shared-links/\(id)") }
    func changeSharedLinkAssets(_ id: String, assetIDs: [String], adding: Bool) async throws {
        struct Body: Encodable { let assetIds: [String] }
        let results: [SharingAssetResult] = try await send(adding ? "PUT" : "DELETE", "shared-links/\(id)/assets", body: Body(assetIds: assetIDs))
        let failures = results.filter { !$0.success && $0.error != "duplicate" }
        if !failures.isEmpty { throw ImmichError.http(400, "\(failures.count) photos couldn't be updated in the link.") }
    }
    func sharingPartners(direction: String) async throws -> [SharingPartner] {
        try await get("partners", query: ["direction": direction])
    }
    func sharingUsers() async throws -> [User] { try await get("users") }
    func addSharingPartner(_ id: String) async throws {
        struct Body: Encodable { let sharedWithId: String }
        try await send("POST", "partners", body: Body(sharedWithId: id))
    }
    func removeSharingPartner(_ id: String) async throws { try await send("DELETE", "partners/\(id)") }
    func updateSharingPartner(_ id: String, inTimeline: Bool) async throws {
        struct Body: Encodable { let inTimeline: Bool }
        try await send("PUT", "partners/\(id)", body: Body(inTimeline: inTimeline))
    }
    func sharingPublicURL(_ link: SharedLink) async throws -> URL {
        struct Config: Decodable { var externalDomain: String? }
        let config: Config? = try? await get("server/config")
        return try Self.sharingURL(link, externalDomain: config?.externalDomain, serverURL: serverURL)
    }
    static func sharingURL(_ link: SharedLink, externalDomain: String?, serverURL: URL) throws -> URL {
        let base = externalDomain.flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? serverURL
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false), ["http", "https"].contains(c.scheme), c.host != nil else { throw ImmichError.invalidServerURL }
        let value = link.slug.flatMap { $0.isEmpty ? nil : $0 }
        let encoded = (value ?? link.key).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()")))!
        c.percentEncodedPath = (value == nil ? "/share/" : "/s/") + encoded
        c.query = nil
        c.fragment = nil
        guard let url = c.url else { throw ImmichError.invalidServerURL }
        return url
    }
}
