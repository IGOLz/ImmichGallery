// Offline regression checks. Run from the repository root:
// swiftc ImmichGallery/API/{Models,Models+Albums,ImmichClient,ImmichClient+Albums}.swift \
//   ImmichGallery/App/AlbumsActions.swift ImmichGallery/Views/Albums/AlbumAssetTransfer.swift \
//   scripts/verify-album-review.swift -o build/verify-album-review && build/verify-album-review
import Foundation
import UniformTypeIdentifiers

final class AlbumProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var sharedStatus = 200
    static let album = """
    {"id":"album","albumName":"Album","assetCount":0,"shared":true}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var recorded = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            recorded.httpBody = body
        }
        Self.requests.append(recorded)
        let shared = request.url!.query != nil
        let status = shared ? Self.sharedStatus : 200
        let json = request.httpMethod == "POST" ? Self.album : "[\(Self.album)]"
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: Data(json.utf8))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Narrow test doubles for the action coordinator; no app, Keychain or network.
enum GridSource { case album(String), library }
@MainActor final class AssetGridModel { var selection: Set<String> = [] }
@MainActor final class LibrarySession {
    var invalidated: [String] = []
    var reloads = 0
    func invalidateAlbumGrid(_ id: String) { invalidated.append(id) }
    func reloadAlbums() async { reloads += 1 }
    func handle(_ error: Error) {}
}

@main
struct VerifyAlbumReview {
    @MainActor static func main() async throws {
        let decoder = JSONDecoder()
        func album(_ fields: String) throws -> Album {
            try decoder.decode(Album.self, from: Data("""
            {"id":"album","albumName":"Album","assetCount":0,"shared":true,\(fields)}
            """.utf8))
        }
        for role in ["owner", "editor", "viewer"] {
            let value = try album("""
            "albumUsers":[{"role":"\(role)","user":{"id":"me","email":"me@example.com","name":"Me"}}]
            """)
            assert(value.canEdit("me") == (role != "viewer"))
            assert(!value.canEdit(nil) && !value.canEdit("stranger"))
        }
        let legacy = try album("""
        "owner":{"id":"me","email":"me@example.com","name":"Me"}
        """)
        assert(legacy.canEdit("me") && !legacy.canEdit("stranger"))
        let ownerID = try album("\"ownerId\":\"me\"")
        assert(ownerID.canEdit("me"))
        let noMembers = try album("\"albumUsers\":[]")
        assert(!noMembers.canEdit("me"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlbumProtocol.self]
        let url = URL(string: "https://demo.immich.app")!
        let client = ImmichClient(serverURL: url, apiURL: url.appendingPathComponent("api"),
                                  credential: nil, session: URLSession(configuration: configuration))
        AlbumProtocol.sharedStatus = 500
        let modern = try await client.albumCollections(legacy: false)
        assert(modern.count == 1 && AlbumProtocol.requests.count == 1)
        AlbumProtocol.requests = []
        AlbumProtocol.sharedStatus = 200
        let old = try await client.albumCollections(legacy: true)
        assert(old.count == 1 && AlbumProtocol.requests.count == 2)
        assert(AlbumProtocol.requests.last!.url!.query == "shared=true")
        AlbumProtocol.sharedStatus = 404
        let fallback = try await client.albumCollections(legacy: true)
        assert(fallback.count == 1)
        _ = try await client.createAlbum(name: "Created", description: "Description", assetIDs: ["asset"])
        let body = try JSONSerialization.jsonObject(with: AlbumProtocol.requests.last!.httpBody!) as! [String: Any]
        assert(body["description"] as? String == "Description" && body["assetIds"] as? [String] == ["asset"])

        let actions = AlbumsActions()
        let session = LibrarySession()
        actions.perform(session: session, albumID: "A") {}
        while session.reloads < 1 { await Task.yield() }
        assert(actions.revisions["A"] == 1 && actions.revisions["B"] == nil)
        assert(session.invalidated == ["A"])
        actions.perform(session: session, albumID: "B", reloadTimeline: false) {}
        while session.reloads < 2 { await Task.yield() }
        assert(actions.revisions["B"] == nil && session.invalidated == ["A"])
        let model = AssetGridModel()
        model.selection = ["selected", "other"]
        actions.newAlbum(ids: ["selected"], model: model)
        actions.didCreate("created")
        assert(model.selection.isEmpty && actions.navigationAlbumID == "created")

        let payload = AlbumAssetTransfer(ids: [UUID().uuidString, UUID().uuidString])
        let copy = try decoder.decode(AlbumAssetTransfer.self, from: JSONEncoder().encode(payload))
        assert(copy.ids == payload.ids)
        assert(UTType.albumAssetIDs.conforms(to: .data))
        assert(!UTType.albumAssetIDs.conforms(to: .text))
        print("PASS: v2/v3 collection requests and dedupe, owner/editor/viewer permissions, create description, per-album invalidation, creation navigation/selection, private drag data")
    }
}
