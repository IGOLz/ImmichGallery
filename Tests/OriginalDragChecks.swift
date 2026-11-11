// Offline checks of the grid/viewer drag payload (issue #44), through real NSItemProviders.
// Run by scripts/check-integration.py ('original-drag'). URLProtocol fixtures only; no app launch, no network.
import AppKit
import Foundation
import Synchronization
import UniformTypeIdentifiers

final class OriginalFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let held = Mutex<OriginalFixtureProtocol?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.url!.deletingLastPathComponent().lastPathComponent
        if id == "held" { Self.held.withLock { $0 = self }; return }
        respond(id: id)
    }
    func respond(id: String) {
        let failed = id == "missing"
        let headers = failed ? [:] : ["Content-Type": "image/heic", "Content-Disposition": "attachment; filename=\"IMG_0001.HEIC\""]
        let response = HTTPURLResponse(url: request.url!, statusCode: failed ? 404 : 200, httpVersion: nil, headerFields: headers)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: Data("original-\(id)".utf8))
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

    /// The bytes and name a receiver such as the Finder gets for the advertised file.
    static func file(_ provider: NSItemProvider) async -> Result<(String, Data), Error> {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in
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
        let data = UTType.data.identifier, marker = UTType.immichOriginalDrag.identifier, ids = UTType.albumAssetIDs.identifier

        // Grid item: the original file first, then in-app marker and album IDs. Never JSON alone.
        let grid = provider(OriginalTransfer(id: "a", client: client, albumIDs: ["a"]))
        precondition(grid.registeredTypeIdentifiers == [data, marker, ids], "\(grid.registeredTypeIdentifiers)")
        precondition(grid.hasRepresentationConforming(toTypeIdentifier: data, fileOptions: []))
        precondition(UploadDropPolicy.isInternal([grid], pasteboard: .withUniqueName()), "Upload targets reject grid drags")
        guard case .success(let (name, bytes)) = await file(grid) else { preconditionFailure("Grid drag must export the original") }
        precondition(name == "IMG_0001.HEIC" && bytes == Data("original-a".utf8), "Original bytes with the real filename, got \(name)")
        let gridIDs = await albumIDs(grid)
        precondition(gridIDs == ["a"], "Album rows still read the asset IDs")

        // Duplicate original filenames from a multi-item drag stay separate files.
        guard case .success(let (otherName, otherBytes)) = await file(provider(OriginalTransfer(id: "b", client: client, albumIDs: ["b"]))) else {
            preconditionFailure("Second item must export")
        }
        precondition(otherName == name && otherBytes == Data("original-b".utf8))
        let cached = (fm.enumerator(at: root.appendingPathComponent("Drags"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent == "IMG_0001.HEIC" }
        let cachedBytes = Set(try cached.map { try Data(contentsOf: $0) })
        precondition(cachedBytes == [Data("original-a".utf8), Data("original-b".utf8)], "Same-named originals must not overwrite each other")

        // A container drag delivers one item per asset; album drops add each ID once, in order.
        precondition(AlbumAssetTransfer.mergedIDs([.init(ids: ["a", "b"]), .init(ids: ["b", "c"]), .init(ids: ["a"])]) == ["a", "b", "c"])

        // Viewer and Locked Folder items: file and marker only, no album IDs.
        let locked = provider(OriginalTransfer(id: "a", client: lockedClient))
        precondition(locked.registeredTypeIdentifiers == [data, marker], "\(locked.registeredTypeIdentifiers)")
        let lockedIDs = await albumIDs(locked)
        precondition(lockedIDs == nil)
        precondition(UploadDropPolicy.isInternal([locked], pasteboard: .withUniqueName()))

        // A failed download fails the drag rather than handing over anything else.
        guard case .failure = await file(provider(OriginalTransfer(id: "missing", client: client, albumIDs: ["missing"]))) else {
            preconditionFailure("A failed download must not succeed")
        }

        // Locking during a download: the revoked directory is never recreated and the drag fails.
        let pending = Task { await file(provider(OriginalTransfer(id: "held", client: lockedClient))) }
        while OriginalFixtureProtocol.held.withLock({ $0 == nil }) { try await Task.sleep(for: .milliseconds(10)) }
        MacTransferCache.discard(root: lockedRoot)
        OriginalFixtureProtocol.held.withLock { $0 }!.respond(id: "held")
        guard case .failure = await pending.value else { preconditionFailure("Locked drag must fail after locking") }
        precondition(!fm.fileExists(atPath: lockedRoot.path), "Locked transfer root must stay deleted")

        print("Original drag checks passed: file first with real name, in-app IDs/marker, duplicates, failure, Locked Folder revocation")
    }
}
