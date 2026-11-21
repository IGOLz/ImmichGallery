import Foundation
import CFNetwork
import Darwin
import Network
import Synchronization

struct ServerProxy: Codable, Equatable, Sendable {
    let host: String
    let port: UInt16
    let username: String?
    let password: String?

    init(host: String, port: String, username: String, password: String) throws {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        let hostname = !host.isEmpty && host.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        }
        guard hostname || IPv6Address(host) != nil,
              let port = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0,
              !username.isEmpty || password.isEmpty else { throw ImmichError.invalidProxy }
        self.host = host.lowercased()
        self.port = port
        self.username = username.isEmpty ? nil : username
        self.password = username.isEmpty ? nil : password
    }

    func configure(_ configuration: URLSessionConfiguration) {
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!))
        if let username, let password { proxy.applyCredential(username: username, password: password) }
        proxy.allowFailover = false
        configuration.proxyConfigurations = [proxy]
    }

    static func serverKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        while components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath.removeLast() }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    static func validateOrigin(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
              url.user == nil, url.password == nil else { throw ImmichError.proxyRequiresHTTPS }
        // URLSession can route literal IP addresses and localhost directly even with failover disabled.
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        var address = in_addr()
        if name == "localhost" || name.hasSuffix(".localhost") || inet_aton(name, &address) != 0 || name.contains(":") {
            throw ImmichError.proxyRequiresHostname
        }
    }
}

/// Cancel the account session and its dedicated sessions together when the route changes.
final class ImmichSessionScope: Sendable {
    private struct Operation {
        let cancel: @Sendable () -> Void
        let wait: @Sendable () async -> Void
    }
    private struct Entry {
        weak var session: URLSession?
        var acceptingRequests = true
        var pending: [UUID: Operation] = [:]
    }
    private struct State {
        var acceptingSessions = true
        var sessions: [ObjectIdentifier: Entry] = [:]
    }
    private let state = Mutex(State())

    deinit { invalidate() }

    func register(_ session: URLSession) {
        let registered = state.withLock { state in
            guard state.acceptingSessions else { return false }
            state.sessions = state.sessions.filter { $0.value.session != nil }
            state.sessions[ObjectIdentifier(session)] = Entry(session: session)
            return true
        }
        if !registered { session.invalidateAndCancel() }
    }

    func withSession<T: Sendable>(_ session: URLSession, _ work: @escaping @Sendable (URLSession) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let sessionID = ObjectIdentifier(session)
        let requestID = UUID()
        let task = try state.withLock { state in
            guard state.sessions[sessionID]?.acceptingRequests == true else { throw CancellationError() }
            let task = Task {
                try Task.checkCancellation()
                return try await work(session)
            }
            state.sessions[sessionID]?.pending[requestID] = Operation(cancel: { task.cancel() }, wait: { _ = await task.result })
            return task
        }
        defer {
            let retired = state.withLock { state -> URLSession? in
                state.sessions[sessionID]?.pending.removeValue(forKey: requestID)
                if let entry = state.sessions[sessionID], !entry.acceptingRequests, entry.pending.isEmpty {
                    return state.sessions.removeValue(forKey: sessionID)?.session
                }
                return nil
            }
            retired?.invalidateAndCancel()
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    /// Invalidated URLSessions crash on task creation. Refuse new work and wait for active callers to unwind.
    func invalidate(_ session: URLSession? = nil, cancelPending: Bool = true) {
        _ = retire(session, cancelPending: cancelPending)
    }

    func invalidateAndWait() async {
        for operation in retire(nil, cancelPending: true) { await operation.wait() }
    }

    private func retire(_ session: URLSession?, cancelPending: Bool) -> [Operation] {
        let (cancel, retired) = state.withLock { state -> ([Operation], [URLSession]) in
            if session == nil { state.acceptingSessions = false }
            let ids = session.map { [ObjectIdentifier($0)] } ?? Array(state.sessions.keys)
            var cancel: [Operation] = []
            var retired: [URLSession] = []
            for id in ids {
                guard let entry = state.sessions[id] else { continue }
                if entry.pending.isEmpty {
                    if let session = state.sessions.removeValue(forKey: id)?.session { retired.append(session) }
                } else {
                    state.sessions[id]?.acceptingRequests = false
                    if cancelPending { cancel.append(contentsOf: entry.pending.values) }
                }
            }
            return (cancel, retired)
        }
        cancel.forEach { $0.cancel() }
        retired.forEach { $0.invalidateAndCancel() }
        return cancel
    }
}

private final class ProxyRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let destination = request.url, (try? ServerProxy.validateOrigin(destination)) != nil else {
            completionHandler(nil)
            return
        }
        let original = task.originalRequest
        let carriesCredentials = original?.value(forHTTPHeaderField: "Authorization") != nil
            || original?.value(forHTTPHeaderField: "x-api-key") != nil
            || original?.httpMethod != "GET"
        if carriesCredentials {
            guard let origin = original?.url, origin.host()?.lowercased() == destination.host()?.lowercased(),
                  (origin.port ?? 443) == (destination.port ?? 443) else { completionHandler(nil); return }
        }
        completionHandler(request)
    }
}

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
    case invalidProxy
    case proxyRequiresHTTPS
    case proxyRequiresHostname
    case proxyAuthentication
    case proxyConnection
    case proxyTLS
    case serverUnreachable(String)
    case unauthorized(String?)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "That doesn't look like a valid server address.")
        case .invalidProxy:
            String(localized: "Enter a proxy hostname or IP address and a port from 1 to 65535. Enter a username if you supply a password.")
        case .proxyRequiresHTTPS:
            String(localized: "HTTP CONNECT requires an HTTPS Immich server address.")
        case .proxyRequiresHostname:
            String(localized: "Enter an Immich server hostname. macOS can bypass the proxy for IP addresses and localhost.")
        case .proxyAuthentication:
            String(localized: "The proxy rejected the connection. Check the proxy username and password.")
        case .proxyConnection:
            String(localized: "Couldn't connect through the HTTP CONNECT proxy. Check the proxy address and whether it can reach the server.")
        case .proxyTLS:
            String(localized: "Couldn't establish a secure connection to the Immich server through the proxy. Check the server's HTTPS certificate.")
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
    let proxy: ServerProxy?
    private let sessionScope: ImmichSessionScope?
    /// Where originals for Quick Look, drags and copied files go when not the shared temporary folders (Locked Folder).
    let transferRoot: URL?

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "ImmichGallery/\(version) (macOS \(os.majorVersion).\(os.minorVersion))"
    }()

    /// Bootstrap session. Media caching begins only after choosing an account identity.
    static let sharedSession = makeSession(bootstrapConfiguration(), proxy: nil)

    private static func bootstrapConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        // Authentication and bootstrap requests do not need a persistent media cache.
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        return config
    }

    static func makeSession(_ configuration: URLSessionConfiguration, proxy: ServerProxy?) -> URLSession {
        guard let proxy else { return URLSession(configuration: configuration) }
        proxy.configure(configuration)
        return URLSession(configuration: configuration, delegate: ProxyRedirectDelegate(), delegateQueue: nil)
    }

    init(serverURL: URL, apiURL: URL, credential: Credential?, session: URLSession? = nil,
         transferRoot: URL? = nil, proxy: ServerProxy? = nil, sessionScope: ImmichSessionScope? = nil) {
        self.serverURL = serverURL
        self.apiURL = apiURL
        self.credential = credential
        self.proxy = proxy
        if let session {
            self.session = session
            self.sessionScope = sessionScope
        } else if let proxy {
            let scope = ImmichSessionScope()
            self.session = Self.makeSession(Self.bootstrapConfiguration(), proxy: proxy)
            scope.register(self.session)
            self.sessionScope = scope
        } else {
            self.session = Self.sharedSession
            self.sessionScope = nil
        }
        self.transferRoot = transferRoot
    }

    func with(credential: Credential) -> ImmichClient {
        ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: session,
                     transferRoot: transferRoot, proxy: proxy, sessionScope: sessionScope)
    }

    func dedicatedSession(_ configuration: URLSessionConfiguration) -> URLSession {
        let session = Self.makeSession(configuration, proxy: proxy)
        sessionScope?.register(session)
        return session
    }

    func isolatedClient(_ configuration: URLSessionConfiguration, transferRoot: URL? = nil) -> ImmichClient {
        ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: dedicatedSession(configuration),
                     transferRoot: transferRoot, proxy: proxy, sessionScope: sessionScope)
    }

    func withSession<T: Sendable>(_ override: URLSession? = nil,
                                 _ work: @escaping @Sendable (URLSession) async throws -> T) async throws -> T {
        let session = override ?? self.session
        if let sessionScope { return try await sessionScope.withSession(session, work) }
        return try await work(session)
    }

    func invalidateSession(_ override: URLSession? = nil, cancelPending: Bool = true) {
        let session = override ?? self.session
        if let sessionScope { sessionScope.invalidate(session, cancelPending: cancelPending) }
        else if cancelPending { session.invalidateAndCancel() }
        else { session.finishTasksAndInvalidate() }
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil,
                  session: URLSession? = nil) async throws -> (URL, URLResponse) {
        do { return try await withSession(session) { try await $0.download(for: request, delegate: delegate) } }
        catch where proxy != nil { throw Self.proxyError(error) }
    }

    static func proxyError(_ error: Error) -> Error {
        let failure = error as NSError
        if error is CancellationError || (failure.domain == NSURLErrorDomain && failure.code == URLError.cancelled.rawValue) { return error }
        var underlying: NSError? = failure
        while let detail = underlying {
            let badProxyCredentials = detail.domain == kCFErrorDomainCFNetwork as String
                && detail.code == Int(CFNetworkErrors.cfErrorHTTPBadProxyCredentials.rawValue)
            let authenticationRejected = detail.domain == NSPOSIXErrorDomain && detail.code == Int(POSIXErrorCode.EAUTH.rawValue)
            if badProxyCredentials || authenticationRejected {
                return ImmichError.proxyAuthentication
            }
            underlying = detail.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if failure.domain == NSURLErrorDomain, (-1206 ... -1200).contains(failure.code) { return ImmichError.proxyTLS }
        return ImmichError.proxyConnection
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
        let data: Data
        let response: URLResponse
        do { (data, response) = try await withSession { try await $0.data(for: request) } }
        catch where proxy != nil { throw Self.proxyError(error) }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            throw ImmichError.unauthorized((try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.text)
        case 407 where proxy != nil:
            throw ImmichError.proxyAuthentication
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
    static func serverCandidates(_ input: String, httpsOnly: Bool = false) -> [URL] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api") { text.removeLast(4) }
        guard !text.isEmpty else { return [] }

        let candidates = text.contains("://") ? [text] : httpsOnly ? ["https://\(text)"] : ["https://\(text)", "http://\(text)"]
        return candidates.compactMap { URL(string: $0) }.filter { $0.host() != nil }
    }

    static func discover(_ input: String, proxy: ServerProxy? = nil) async throws -> ImmichClient {
        let candidates = serverCandidates(input, httpsOnly: proxy != nil)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        let probe = makeSession(config, proxy: proxy)
        defer { probe.finishTasksAndInvalidate() }

        var lastError: Error = ImmichError.invalidServerURL
        for base in candidates {
            if proxy != nil { try ServerProxy.validateOrigin(base) }
            let api = await wellKnownEndpoint(base: base, session: probe) ?? base.appendingPathComponent("api")
            if proxy != nil { try ServerProxy.validateOrigin(api) }
            let response: (Data, URLResponse)
            do {
                response = try await probe.data(from: api.appendingPathComponent("server/ping"))
            } catch {
                if proxy != nil { throw proxyError(error) }
                lastError = ImmichError.serverUnreachable(error.localizedDescription)
                continue
            }
            let (data, reply) = response
            let status = (reply as? HTTPURLResponse)?.statusCode
            if proxy != nil, status == 407 { throw ImmichError.proxyAuthentication }
            struct Pong: Decodable { let res: String }
            if (proxy == nil || status == 200), (try? JSONDecoder().decode(Pong.self, from: data))?.res == "pong" {
                return ImmichClient(serverURL: base, apiURL: api, credential: nil, proxy: proxy)
            }
            lastError = ImmichError.serverUnreachable(String(localized: "The server answered, but it isn't Immich."))
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
    var withCoordinates: Bool? // Assign Location: GPS badges.

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
            "withCoordinates": withCoordinates.map(String.init),
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
        personIds: [String]? = nil, tagIds: [String]? = nil, order: String = "desc", withExif: Bool? = nil, page: SearchPage, size: Int = 250
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
            var withExif: Bool?
            var withStacked = true
        }
        let body = Body(type: type?.rawValue, originalFileName: fileName, visibility: visibility, isFavorite: isFavorite,
                        personIds: personIds, tagIds: tagIds, page: page.page, cursor: page.cursor, size: size, order: order, withExif: withExif)
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
