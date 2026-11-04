// Offline by default; pass --live for the public demo.
// Run with the API sources: swiftc ImmichGallery/API/*.swift ImmichGallery/App/UploadQueue.swift scripts/verify-upload.swift -o /tmp/verify-upload && /tmp/verify-upload
// Uses the public demo. Creates and removes only its own generated image and album.
import Foundation
import AppKit

@main struct VerifyUpload {
    static func main() async {
        do {
            if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--memory" {
                let source = URL(fileURLWithPath: CommandLine.arguments[2])
                _ = try UploadMultipart.checksum(source)
                let body = try UploadMultipart.make(source, legacy: false)
                try FileManager.default.removeItem(at: body.file)
                print("PASS: large-file hash and multipart copy")
            } else { try await verify() }
        }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
    static func verify() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ImmichGallery-upload-\(UUID().uuidString).png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        for index in 0..<(32 * 32 * 4) { bitmap.bitmapData![index] = UInt8.random(in: 0...255) }
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        let abc = directory.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: abc)
        try require(try UploadMultipart.checksum(abc) == "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=")
        let fixture = try JSONDecoder().decode(UploadResponse.self, from: Data("{\"id\":\"test\",\"status\":\"duplicate\"}".utf8))
        try require(fixture.status == "duplicate")
        let legacy = try UploadMultipart.make(file, legacy: true)
        let legacyData = try Data(contentsOf: legacy.file)
        try require(legacyData.range(of: Data("name=\"deviceId\"".utf8)) != nil)
        try FileManager.default.removeItem(at: legacy.file)
        let body = try UploadMultipart.make(file, legacy: false)
        let bodyData = try Data(contentsOf: body.file)
        try require(bodyData.range(of: Data("name=\"assetData\"".utf8)) != nil)
        try require(bodyData.range(of: try Data(contentsOf: file)) != nil)
        try FileManager.default.removeItem(at: body.file)
        let nested = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedFile = nested.appendingPathComponent("photo.jpg")
        try Data("nested".utf8).write(to: nestedFile)
        let hidden = directory.appendingPathComponent(".hidden")
        try Data("hidden".utf8).write(to: hidden)
        let link = directory.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: nestedFile)
        let scanned = try UploadQueue.scan([directory, file]).urls
        try require(scanned.contains(nestedFile) && scanned.filter { $0 == file }.count == 1)
        try require(!scanned.contains(hidden) && !scanned.contains(link))
        let partial = try UploadQueue.scan([directory.appendingPathComponent("missing"), nestedFile])
        try require(partial.unreadableCount == 1 && partial.urls == [nestedFile])
        let stale = directory.appendingPathComponent("ImmichGallery-upload-2147483647-test")
        let active = directory.appendingPathComponent("ImmichGallery-upload-\(ProcessInfo.processInfo.processIdentifier)-test")
        try Data().write(to: stale)
        try Data().write(to: active)
        UploadMultipart.sweepStale(in: directory)
        try require(!FileManager.default.fileExists(atPath: stale.path) && FileManager.default.fileExists(atPath: active.path))
        try await verifyQueue(file: file, directory: directory)
        print("PASS: SHA-1, multipart preservation, recursive/partial scan, deduplication, hidden/symlink exclusion, stale-body cleanup")
        if !CommandLine.arguments.contains("--live") { return }
        let server = URL(string: "https://demo.immich.app")!
        let anonymous = ImmichClient(serverURL: server, apiURL: server.appendingPathComponent("api"), credential: nil)
        print("Checking demo login")
        let login = try await anonymous.login(email: "demo@immich.app", password: "demo")
        let client = anonymous.with(credential: .accessToken(login.accessToken))
        var assetID: String?
        var albumID: String?
        do {
            print("Checking version and media types")
            let version = try await client.serverVersion()
            let types = try await client.uploadMediaTypes()
            try require(types.extensions.contains(".png"))
            let checksum = try UploadMultipart.checksum(file)
            print("Checking duplicate preflight")
            let before = try await client.checkUpload(checksum: checksum, name: file.lastPathComponent)
            try require(before.results.first?.action == "accept")
            print("Checking new upload")
            let uploaded = try await client.uploadFile(file, checksum: checksum, legacy: version.major < 3) { sent, total in
                assert(sent >= 0 && total > 0)
            }
            guard uploaded.status == "created" else { throw URLError(.badServerResponse) }
            assetID = uploaded.id
            let after = try await client.checkUpload(checksum: checksum, name: file.lastPathComponent)
            try require(after.results.first?.assetId == assetID && after.results.first?.action == "reject")
            let duplicate = try await client.uploadFile(file, checksum: checksum, legacy: false) { _, _ in }
            try require(duplicate.status == "duplicate" && duplicate.id == assetID)
            struct AlbumBody: Encodable { let albumName: String }
            struct NewAlbum: Decodable { let id: String }
            print("Checking album creation")
            let album: NewAlbum = try await client.send("POST", "albums", body: AlbumBody(albumName: "ImmichGallery upload verification \(UUID().uuidString)"))
            albumID = album.id
            try await client.addUploadToAlbum(uploaded.id, albumID: album.id)
            try await client.addUploadToAlbum(uploaded.id, albumID: album.id)
            print("PASS: server \(version), media types, SHA-1, multipart, new upload, duplicate preflight/header, album addition and duplicate membership")
        } catch {
            try await cleanup(client, assetID: assetID, albumID: albumID)
            try? await client.logout()
            throw error
        }
        try await cleanup(client, assetID: assetID, albumID: albumID)
        try await client.logout()
        print("PASS: deleted only the generated test asset and test album; logged out test session")
    }
    @MainActor static func verifyQueue(file: URL, directory: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UploadFixtureProtocol.self]
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let server = URL(string: "https://demo.immich.app")!
        let client = ImmichClient(serverURL: server, apiURL: server.appendingPathComponent("api"), credential: nil, session: session)
        let queue = UploadQueue(client: client)
        var refreshes = 0
        queue.onFinished = { refreshes += 1 }
        queue.enqueue([file, file], albumID: "fixture-album")
        try require(queue.showingProgress)
        try await settle(queue)
        try require(queue.items.count == 1 && queue.duplicates == 1 && queue.completed == 1)
        try require(queue.items.first?.response?.isTrashed == true && refreshes == 1)
        try require(UploadFixtureProtocol.albumRequests == 1)
        queue.enqueue([file], albumID: "fixture-album")
        try await settle(queue)
        try require(refreshes == 1)
        let ignored = directory.appendingPathComponent("unsupported.txt")
        try Data().write(to: ignored)
        queue.enqueue([ignored, directory.appendingPathComponent("missing")])
        try await settle(queue)
        try require(queue.unsupportedCount == 1 && queue.unreadableCount == 1 && queue.items.count == 1 && refreshes == 1)
        queue.clear()
        try require(queue.completed == 0 && queue.duplicates == 0)
        let deniedClient = ImmichClient(serverURL: server, apiURL: server.appendingPathComponent("api"),
                                        credential: .apiKey("fixture-denied"), session: session)
        let denied = UploadQueue(client: deniedClient)
        var unauthorized = 0
        denied.onError = { if case ImmichError.unauthorized = $0 { unauthorized += 1 } }
        denied.enqueue([file])
        try await settle(denied)
        try require(denied.failed == 1 && unauthorized == 1 && denied.revision == 0 && denied.showingProgress)
        denied.retryFailed()
        try await settle(denied)
        try require(denied.failed == 1 && denied.completed == 1 && unauthorized == 2)
        denied.clear()
        // The upload session must preserve URLProtocol while replacing the shared 30-second timeout.
        let result = try await client.uploadFile(file, checksum: UploadMultipart.checksum(file), legacy: false) { _, _ in }
        try require(result.status == "created" && UploadFixtureProtocol.uploadTimeout == 3600)
        print("PASS: queue counters/deduplication, trashed duplicate + album, ignored/unreadable warnings, idle refresh gate, 401 routing/retry, upload timeout")
    }

    @MainActor static func settle(_ queue: UploadQueue) async throws {
        let deadline = Date().addingTimeInterval(10)
        while queue.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try require(!queue.isRunning)
    }

    static func require(_ condition: Bool) throws {
        if !condition { throw URLError(.badServerResponse) }
    }
    static func cleanup(_ client: ImmichClient, assetID: String?, albumID: String?) async throws {
        if let albumID { try await client.send("DELETE", "albums/\(albumID)") }
        if let assetID { try await client.delete([assetID], force: true) }
    }
}

// All requests in offline checks are intercepted; no network connection is opened.
private final class UploadFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var albums = 0
    private static var timeout: TimeInterval = 0
    static var albumRequests: Int { lock.withLock { albums } }
    static var uploadTimeout: TimeInterval { lock.withLock { timeout } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        var code = 200
        let body: String
        switch path {
        case "/api/server/media-types": body = #"{"image":[".png"],"video":[],"sidecar":[]}"#
        case "/api/server/version": body = #"{"major":3,"minor":3,"patch":5}"#
        case "/api/assets/bulk-upload-check":
            if request.value(forHTTPHeaderField: "x-api-key") == "fixture-denied" {
                code = 401; body = #"{"message":"Fixture expired session"}"#
            } else {
                body = #"{"results":[{"id":"fixture","action":"reject","assetId":"own-fixture","isTrashed":true}]}"#
            }
        case "/api/albums/fixture-album/assets":
            Self.lock.withLock { Self.albums += 1 }
            body = #"[{"id":"own-fixture","success":true}]"#
        case "/api/assets":
            Self.lock.withLock { Self.timeout = request.timeoutInterval }
            body = #"{"id":"own-fixture","status":"created"}"#
        default: fatalError("Unexpected fixture request: \(path)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
