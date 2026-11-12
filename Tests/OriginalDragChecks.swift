// Offline checks of the grid/viewer drag payload (issues #44, #51), through real NSItemProviders.
// Run by scripts/check-integration.py ('original-drag'). URLProtocol fixtures only; no app launch, no network.
// What a receiver negotiates before the drop (advertised type, suggested name: the Finder names its file from it)
// is checked here; the Finder and other apps themselves still need a manual drop.
import AppKit
import Foundation
import Synchronization
import UniformTypeIdentifiers

/// Fixture server. `assets/{id}` answers the details (name and kind), `assets/{id}/original` the bytes.
final class OriginalFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let held = Mutex<OriginalFixtureProtocol?>(nil)
    static let stalled = Mutex<[OriginalFixtureProtocol]>([])
    static let detailRequests = Mutex<[String]>([])
    static let details: [String: (type: String, name: String)] = [
        "a": ("IMAGE", "IMG_0001.HEIC"), "b": ("IMAGE", "IMG_0001.HEIC"), "held": ("IMAGE", "IMG_0001.HEIC"),
        "v": ("VIDEO", "MOV_0002.MOV"), "raw": ("IMAGE", "DSC_0003.NEF"), "audio": ("AUDIO", "voice.m4a"),
        "path": ("IMAGE", "../../Escape.JPG"),
        "p1": ("IMAGE", "P1.JPG"), "p2": ("IMAGE", "P2.JPG"), "p3": ("IMAGE", "P3.JPG"), "p4": ("IMAGE", "P4.JPG"),
    ]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.lastPathComponent == "original" {
            let id = url.deletingLastPathComponent().lastPathComponent
            if id == "held" { Self.held.withLock { $0 = self }; return }
            respond(id: id)
        } else {
            let id = url.lastPathComponent
            Self.detailRequests.withLock { $0.append(id) }
            if id == "slow" { Self.stalled.withLock { $0.append(self) }; return }
            let reply = { [self] in
                guard let detail = Self.details[id] else { return send(status: 404, headers: [:], body: Data()) }
                let json: [String: Any] = ["id": id, "type": detail.type, "originalFileName": detail.name, "fileCreatedAt": "2024-01-01T00:00:00.000Z",
                                           "localDateTime": "2024-01-01T00:00:00.000Z", "isFavorite": false, "isTrashed": false]
                send(status: 200, headers: ["Content-Type": "application/json"], body: try! JSONSerialization.data(withJSONObject: json))
            }
            // Multi-item drags: the details of several items take one round trip, not one each.
            if id.hasPrefix("p") { DispatchQueue.global().asyncAfter(deadline: .now() + 0.4, execute: reply) } else { reply() }
        }
    }
    func respond(id: String) {
        let failed = id == "missing"
        let name = Self.details[id]?.name ?? "Unknown.bin"
        send(status: failed ? 404 : 200, headers: failed ? [:] : ["Content-Disposition": "attachment; filename=\"\(name)\""], body: Data("original-\(id)".utf8))
    }
    func send(status: Int, headers: [String: String], body: Data) {
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
                            cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: body)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OriginalDragChecks {
    static func provider(_ item: OriginalTransfer) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.register(item)
        return provider
    }

    /// The bytes and name a receiver gets by loading the advertised type. `whileOpen` runs while the receiver
    /// still holds the file, as a receiver reading it later would.
    static func file(_ provider: NSItemProvider, whileOpen: @escaping @Sendable () -> Void = {}) async -> Result<(String, Data), Error> {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers[0]) { url, error in
                whileOpen()
                if let url, let data = try? Data(contentsOf: url) { continuation.resume(returning: .success((url.lastPathComponent, data))) }
                else { continuation.resume(returning: .failure(error ?? CocoaError(.fileReadUnknown))) }
            }
        }
    }

    static func albumIDs(_ provider: NSItemProvider) async -> [String]? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: AlbumAssetTransfer.self) { continuation.resume(returning: try? $0.get().ids) }
        }
    }

    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("original-drag-test-" + UUID().uuidString, isDirectory: true)
        let lockedRoot = root.appendingPathComponent("Locked", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OriginalFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let server = URL(string: "https://fixture.invalid/api")!
        let client = ImmichClient(serverURL: server, apiURL: server, credential: nil, session: session, transferRoot: root)
        let lockedClient = ImmichClient(serverURL: server, apiURL: server, credential: nil, session: session, transferRoot: lockedRoot)
        let image = UTType.image.identifier, movie = UTType.movie.identifier, data = UTType.data.identifier
        let marker = UTType.immichOriginalDrag.identifier, ids = UTType.albumAssetIDs.identifier

        // Cells and the viewer build items all the time; only a drag reads the details.
        _ = (0..<100).map { _ in OriginalTransfer(id: "a", client: client, albumIDs: ["a"]) }
        precondition(OriginalFixtureProtocol.detailRequests.withLock { $0.isEmpty }, "Building drag items must not request details")

        // Grid photo: the original first, advertised as an image under its real name (receivers such as the Finder
        // name the file from it before the download), then the in-app marker and album IDs. Never JSON alone.
        let grid = provider(OriginalTransfer(id: "a", client: client, albumIDs: ["a"]))
        precondition(grid.registeredTypeIdentifiers == [image, marker, ids], "\(grid.registeredTypeIdentifiers)")
        precondition(grid.suggestedName == "IMG_0001.HEIC", "\(grid.suggestedName ?? "nil")")
        precondition(grid.hasItemConformingToTypeIdentifier(image) && grid.hasItemConformingToTypeIdentifier(data))
        precondition(!grid.hasItemConformingToTypeIdentifier(movie) && !grid.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier),
                     "A HEIC is not advertised as a movie or a JPEG")
        precondition(UploadDropPolicy.isInternal([grid], pasteboard: .withUniqueName()), "Upload targets reject grid drags")
        // The receiver's file outlives the app's cached original, which expires.
        guard case .success(let (name, bytes)) = await file(grid, whileOpen: { MacTransferCache.prune(root: root, now: .distantFuture) }) else {
            preconditionFailure("Grid drag must export the original")
        }
        precondition(name == "IMG_0001.HEIC" && bytes == Data("original-a".utf8), "Original bytes with the real filename, got \(name)")
        let gridIDs = await albumIDs(grid)
        precondition(gridIDs == ["a"], "Album rows still read the asset IDs")

        // Each kind under its own type and name, bytes unchanged: videos, RAW, and others as plain data.
        for (id, type, expected) in [("v", movie, "MOV_0002.MOV"), ("raw", image, "DSC_0003.NEF"), ("audio", data, "voice.m4a"), ("path", image, "Escape.JPG")] {
            let item = provider(OriginalTransfer(id: id, client: client, albumIDs: [id]))
            precondition(item.registeredTypeIdentifiers == [type, marker, ids], "\(id): \(item.registeredTypeIdentifiers)")
            precondition(item.suggestedName == expected, "\(id): \(item.suggestedName ?? "nil")")
            guard case .success(let (_, bytes)) = await file(item) else { preconditionFailure("\(id) must export") }
            precondition(bytes == Data("original-\(id)".utf8))
        }

        // Details unavailable: generic data named after the asset, never a guessed type; the file still arrives.
        let unknown = provider(OriginalTransfer(id: "nodetails", client: client, albumIDs: ["nodetails"]))
        precondition(unknown.registeredTypeIdentifiers == [data, marker, ids] && unknown.suggestedName == "nodetails")
        guard case .success = await file(unknown) else { preconditionFailure("The original must still export") }

        // Details too slow: the drag starts after the timeout, with the fallback.
        let slowStart = Date()
        let slow = provider(OriginalTransfer(id: "slow", client: client))
        let waited = Date().timeIntervalSince(slowStart)
        precondition(slow.registeredTypeIdentifiers == [data, marker] && slow.suggestedName == "slow")
        precondition(waited >= OriginalFile.timeout * 0.9 && waited < OriginalFile.timeout + 0.5, "Waited \(waited)s")

        // A multi-item drag reads every item's details at once (one 0.4 s round trip, not four).
        let batchStart = Date()
        let batch = ["p1", "p2", "p3", "p4"].map { OriginalTransfer(id: $0, client: client, albumIDs: [$0]) }
        batch.forEach { $0.file.start() }
        let names = batch.map { provider($0).suggestedName }
        let batchTime = Date().timeIntervalSince(batchStart)
        precondition(names == ["P1.JPG", "P2.JPG", "P3.JPG", "P4.JPG"], "\(names)")
        precondition(batchTime < 1, "Details of a multi-item drag took \(batchTime)s")

        // Duplicate original filenames from a multi-item drag stay separate files.
        guard case .success(let (otherName, otherBytes)) = await file(provider(OriginalTransfer(id: "b", client: client, albumIDs: ["b"]))) else {
            preconditionFailure("Second item must export")
        }
        precondition(otherName == name && otherBytes == Data("original-b".utf8))
        guard case .success = await file(provider(OriginalTransfer(id: "a", client: client))) else { preconditionFailure("Again") }
        let cached = (fm.enumerator(at: root.appendingPathComponent("Drags"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent == "IMG_0001.HEIC" }
        let cachedBytes = Set(try cached.map { try Data(contentsOf: $0) })
        precondition(cachedBytes == [Data("original-a".utf8), Data("original-b".utf8)], "Same-named originals must not overwrite each other")

        // A container drag delivers one item per asset; album drops add each ID once, in order.
        precondition(AlbumAssetTransfer.mergedIDs([.init(ids: ["a", "b"]), .init(ids: ["b", "c"]), .init(ids: ["a"])]) == ["a", "b", "c"])

        // Viewer and Locked Folder items: file and marker only, no album IDs.
        let locked = provider(OriginalTransfer(id: "a", client: lockedClient))
        precondition(locked.registeredTypeIdentifiers == [image, marker], "\(locked.registeredTypeIdentifiers)")
        let lockedIDs = await albumIDs(locked)
        precondition(lockedIDs == nil)
        precondition(UploadDropPolicy.isInternal([locked], pasteboard: .withUniqueName()))

        // A failed download fails the drag rather than handing over anything else.
        guard case .failure = await file(provider(OriginalTransfer(id: "missing", client: client, albumIDs: ["missing"]))) else {
            preconditionFailure("A failed download must not succeed")
        }

        // Locking during a download: the revoked directory is never recreated and the drag fails.
        let heldProvider = provider(OriginalTransfer(id: "held", client: lockedClient))
        let pending = Task { await file(heldProvider) }
        while OriginalFixtureProtocol.held.withLock({ $0 == nil }) { try await Task.sleep(for: .milliseconds(10)) }
        MacTransferCache.discard(root: lockedRoot)
        OriginalFixtureProtocol.held.withLock { $0 }!.respond(id: "held")
        guard case .failure = await pending.value else { preconditionFailure("Locked drag must fail after locking") }
        precondition(!fm.fileExists(atPath: lockedRoot.path), "Locked transfer root must stay deleted")

        print("Original drag checks passed: real kind and name before the download, original bytes, receiver copy outlives the cache, fallbacks, multi-item details, in-app IDs/marker, duplicates, failure, Locked Folder revocation")
    }
}
