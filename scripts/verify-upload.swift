// Run with the API sources: swiftc ImmichGallery/API/*.swift ImmichGallery/App/UploadQueue.swift scripts/verify-upload.swift -o /tmp/verify-upload && /tmp/verify-upload
// Uses the public demo. Creates and removes only its own generated image and album.
import Foundation
import AppKit

@main struct VerifyUpload {
    static func main() async {
        do { try await verify() }
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
        let scanned = try UploadQueue.scan([directory, file])
        try require(scanned.contains(nestedFile) && scanned.filter { $0 == file }.count == 1)
        try require(!scanned.contains(hidden) && !scanned.contains(link))
        print("PASS: SHA-1, multipart file preservation, recursive scan, path deduplication, hidden/symlink exclusion")
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
            let library = try await client.metadataSearch(type: .image, page: .init(page: 1), size: 1)
            if let sample = library.items.first {
                struct Existing: Decodable { let checksum: String }
                let existing: Existing = try await client.get("assets/\(sample.id)")
                let known = try await client.checkUpload(checksum: existing.checksum, name: "known-duplicate")
                try require(known.results.first?.assetId == sample.id && known.results.first?.action == "reject")
                print("PASS: real accept/reject duplicate responses decoded")
            }
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
    static func require(_ condition: Bool) throws {
        if !condition { throw URLError(.badServerResponse) }
    }
    static func cleanup(_ client: ImmichClient, assetID: String?, albumID: String?) async throws {
        if let albumID { try await client.send("DELETE", "albums/\(albumID)") }
        if let assetID { try await client.delete([assetID], force: true) }
    }
}
