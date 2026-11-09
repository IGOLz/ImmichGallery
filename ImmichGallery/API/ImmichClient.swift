import Foundation

enum Credential: Codable, Sendable, Equatable {
    /// Session token from `POST /auth/login`. Shows up under "Authorized devices" in Immich.
    case accessToken(String)
    /// API key created in Immich → Account Settings → API Keys.
    case apiKey(String)

    var headers: [String: String] {
        switch self {
        case .accessToken(let token): ["Authorization": "Bearer \(token)"]
        case .apiKey(let key): ["x-api-key": key]
        }
    }
}

enum ImmichError: LocalizedError {
    case invalidServerURL
    case serverUnreachable(String)
    case unauthorized(String?)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "That doesn't look like a valid server address.")
        case .serverUnreachable(let detail):
            String(localized: "Couldn't reach an Immich server at that address. \(detail)")
        case .unauthorized(let message):
            message ?? String(localized: "Your session has expired or the credentials are wrong.")
        case .http(let code, let message):
            message ?? String(localized: "The server returned an error (\(code)).")
        }
    }
}

/// Thin, stateless client for the Immich REST API.
final class ImmichClient: Sendable {
    let serverURL: URL
    let apiURL: URL
    let credential: Credential?
    let session: URLSession

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "ImmichGallery/\(version) (macOS \(os.majorVersion).\(os.minorVersion))"
    }()

    /// Bootstrap session. Media caching begins only after choosing an account identity.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Authentication and bootstrap requests do not need a persistent media cache.
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    init(serverURL: URL, apiURL: URL, credential: Credential?, session: URLSession = ImmichClient.sharedSession) {
        self.serverURL = serverURL
        self.apiURL = apiURL
        self.credential = credential
        self.session = session
    }

    func with(credential: Credential) -> ImmichClient {
        ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: session)
    }

    // MARK: - Request plumbing

    func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var components = URLComponents(url: apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return components.url!
    }

    func request(_ path: String, method: String = "GET", query: [String: String?] = [:], body: (any Encodable)? = nil) throws -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        credential?.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    @discardableResult
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            throw ImmichError.unauthorized((try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.text)
        default:
            let message = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.text
            throw ImmichError.http(http.statusCode, message)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        let data = try await data(for: request(path, query: query))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        let data = try await data(for: request(path, method: method, body: body))
        return try JSONDecoder().decode(T.self, from: data)
    }

    func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        try await data(for: request(path, method: method, body: body))
    }

    private struct ServerErrorBody: Decodable {
        var message: FlexibleMessage?
        var text: String? { message?.text }

        enum FlexibleMessage: Decodable {
            case one(String), many([String])
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .one(s) } else { self = .many(try c.decode([String].self)) }
            }
            var text: String { switch self { case .one(let s): s; case .many(let a): a.joined(separator: "\n") } }
        }
    }
}

// MARK: - Server discovery

extension ImmichClient {
    /// Resolves what the user typed into a reachable Immich API endpoint.
    /// Mirrors the official mobile app: honours `/.well-known/immich`, falls back to `<server>/api`,
    /// and tries https before http when no scheme was given.
    static func discover(_ input: String) async throws -> ImmichClient {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api") { text.removeLast(4) }
        guard !text.isEmpty else { throw ImmichError.invalidServerURL }

        let candidates = text.contains("://") ? [text] : ["https://\(text)", "http://\(text)"]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        let probe = URLSession(configuration: config)

        var lastError: Error = ImmichError.invalidServerURL
        for candidate in candidates {
            guard let base = URL(string: candidate), base.host() != nil else { continue }
            let api = await wellKnownEndpoint(base: base, session: probe) ?? base.appendingPathComponent("api")
            do {
                let (data, _) = try await probe.data(from: api.appendingPathComponent("server/ping"))
                struct Pong: Decodable { let res: String }
                if (try? JSONDecoder().decode(Pong.self, from: data))?.res == "pong" {
                    return ImmichClient(serverURL: base, apiURL: api, credential: nil)
                }
                lastError = ImmichError.serverUnreachable(String(localized: "The server answered, but it isn't Immich."))
            } catch {
                lastError = ImmichError.serverUnreachable(error.localizedDescription)
            }
        }
        throw lastError
    }

    private static func wellKnownEndpoint(base: URL, session: URLSession) async -> URL? {
        struct WellKnown: Decodable { struct API: Decodable { let endpoint: String }; let api: API }
        guard let (data, response) = try? await session.data(from: base.appendingPathComponent(".well-known/immich")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let wellKnown = try? JSONDecoder().decode(WellKnown.self, from: data),
              let url = URL(string: wellKnown.api.endpoint, relativeTo: base)?.absoluteURL
        else { return nil }
        return url
    }
}

// MARK: - Endpoints

/// Filters understood by `GET /timeline/buckets` and `GET /timeline/bucket`.
struct TimelineQuery: Hashable, Sendable {
    var visibility: String? = "timeline"
    var isFavorite: Bool?
    var isTrashed: Bool?
    var albumId: String?
    var personId: String?
    var userId: String? // Sharing
    var tagId: String? // Explore
    var withPartners: Bool?
    var withStacked: Bool? = true
    var bbox: String? // Explore
    var order: String? // Timeline view options: "asc" for oldest first.
    var orderBy: String? // Timeline view options: "createdAt" for date added (Immich v3.0).

    var parameters: [String: String?] {
        [
            "bbox": bbox, // Explore
            "visibility": visibility,
            "isFavorite": isFavorite.map(String.init),
            "isTrashed": isTrashed.map(String.init),
            "albumId": albumId,
            "personId": personId,
            "userId": userId, // Sharing
            "tagId": tagId, // Explore
            "withPartners": withPartners.map(String.init),
            "withStacked": withStacked.map(String.init),
            "order": order,
            "orderBy": orderBy,
        ]
    }
}

extension ImmichClient {
    func serverVersion() async throws -> ServerVersion { try await get("server/version") }
    func serverFeatures() async throws -> ServerFeatures { try await get("server/features") }
    func currentUser() async throws -> User { try await get("users/me") }

    func login(email: String, password: String) async throws -> LoginResponse {
        struct Body: Encodable { let email: String; let password: String }
        return try await send("POST", "auth/login", body: Body(email: email, password: password))
    }

    func logout() async throws { try await send("POST", "auth/logout") }

    func timeBuckets(_ query: TimelineQuery) async throws -> [TimeBucket] {
        try await get("timeline/buckets", query: query.parameters)
    }

    func timeBucket(_ bucket: String, _ query: TimelineQuery) async throws -> TimeBucketAssets {
        var parameters = query.parameters
        parameters["timeBucket"] = bucket
        return try await get("timeline/bucket", query: parameters)
    }

    func asset(_ id: String) async throws -> AssetResponse { try await get("assets/\(id)") }

    /// Owned albums plus albums shared with the user.
    func albums() async throws -> [Album] { try await get("albums") }

    func albums(containing assetID: String) async throws -> [Album] {
        try await get("albums", query: ["assetId": assetID])
    }

    func people(page: Int, size: Int = 500) async throws -> PeopleResponse {
        try await get("people", query: ["page": String(page), "size": String(size), "withHidden": "false"])
    }

    struct SearchPage: Sendable {
        var page: Int?
        var cursor: String?
    }

    /// Smart (CLIP) search. Uses `page` paging, which every server version understands.
    func smartSearch(_ text: String, page: Int, size: Int = 100) async throws -> SearchResponse.Assets {
        struct Body: Encodable { let query: String; let page: Int; let size: Int }
        let response: SearchResponse = try await send("POST", "search/smart", body: Body(query: text, page: page, size: size))
        return response.assets
    }

    /// Metadata search (used for filename search and media-type collections).
    func metadataSearch(
        type: AssetType? = nil, fileName: String? = nil, visibility: String? = nil, isFavorite: Bool? = nil,
        personIds: [String]? = nil, tagIds: [String]? = nil, order: String = "desc", page: SearchPage, size: Int = 250
    ) async throws -> SearchResponse.Assets {
        struct Body: Encodable {
            var type: String?
            var originalFileName: String?
            var visibility: String?
            var isFavorite: Bool?
            var personIds: [String]?
            var tagIds: [String]?
            var page: Int?
            var cursor: String?
            var size: Int
            var order: String
            var withStacked = true
        }
        let body = Body(type: type?.rawValue, originalFileName: fileName, visibility: visibility, isFavorite: isFavorite,
                        personIds: personIds, tagIds: tagIds, page: page.page, cursor: page.cursor, size: size, order: order)
        let response: SearchResponse = try await send("POST", "search/metadata", body: body)
        return response.assets
    }

    func setFavorite(_ ids: [String], _ isFavorite: Bool) async throws {
        struct Body: Encodable { let ids: [String]; let isFavorite: Bool }
        try await send("PUT", "assets", body: Body(ids: ids, isFavorite: isFavorite))
    }

    func setVisibility(_ ids: [String], _ visibility: String) async throws {
        struct Body: Encodable { let ids: [String]; let visibility: String }
        try await send("PUT", "assets", body: Body(ids: ids, visibility: visibility))
    }

    /// Moves to trash, or deletes permanently when `force` is true.
    func delete(_ ids: [String], force: Bool) async throws {
        struct Body: Encodable { let ids: [String]; let force: Bool }
        try await send("DELETE", "assets", body: Body(ids: ids, force: force))
    }

    func restore(_ ids: [String]) async throws {
        struct Body: Encodable { let ids: [String] }
        try await send("POST", "trash/restore/assets", body: Body(ids: ids))
    }

    // MARK: Media URLs

    enum ThumbnailSize: String, Sendable { case thumbnail, preview, fullsize }

    func thumbnailRequest(_ id: String, size: ThumbnailSize, edited: Bool = true) -> URLRequest {
        try! request("assets/\(id)/thumbnail", query: ["size": size.rawValue, "edited": String(edited)])
    }

    func originalRequest(_ id: String, edited: Bool = false) -> URLRequest {
        try! request("assets/\(id)/original", query: ["edited": String(edited)])
    }

    func personThumbnailRequest(_ id: String) -> URLRequest {
        try! request("people/\(id)/thumbnail")
    }

    func videoURL(_ id: String) -> URL { url("assets/\(id)/video/playback") }
}
