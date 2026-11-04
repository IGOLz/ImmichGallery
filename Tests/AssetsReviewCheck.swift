import Foundation

// Compile with Models.swift, Models+Assets.swift, ImmichClient.swift, ImmichClient+Assets.swift,
// and the unmodified AssetsDownloadProgress declaration extracted from AssetsDownloader.swift.
// Pass --demo to run a read-only ZIP download against the public demo. No Keychain access.
@main struct AssetsReviewCheck {
    static func main() async throws {
        assert(AssetsCoordinates.parse("48,85") == 48.85)
        assert(AssetsCoordinates.parse(" -12.5 ") == -12.5)
        assert(AssetsCoordinates.parse("1,234.56") == nil)
        assert(AssetsCoordinates.parse("bad") == nil)
        let decoder = JSONDecoder()
        let missing = try decoder.decode(ServerFeatures.self, from: Data("{}".utf8))
        let enabled = try decoder.decode(ServerFeatures.self, from: Data(#"{"duplicateDetection":true}"#.utf8))
        assert(missing.duplicateDetection == nil && enabled.duplicateDetection == true)
        let bucket = try decoder.decode(TimeBucketAssets.self, from: Data(#"{"id":["a"],"ownerId":["owner"],"isImage":[true],"isFavorite":[false],"isTrashed":[false],"thumbhash":[null],"ratio":[1],"duration":[null],"fileCreatedAt":["2026-01-01"],"livePhotoVideoId":[null]}"#.utf8))
        assert(bucket.ownerId == ["owner"])
        let network = URLSession(configuration: .ephemeral)
        defer { network.invalidateAndCancel() }
        let client = ImmichClient(serverURL: URL(string: "https://demo.immich.app")!, apiURL: URL(string: "https://demo.immich.app/api")!, credential: nil, session: network)
        let request = try client.assetsArchiveRequest(["first", "second"], archiveName: "Review-Check")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        assert(body["assetIds"] as? [String] == ["first", "second"])
        assert(body["archiveName"] as? String == "Review-Check")
        print("Coordinate, feature compatibility, timeline owner, and archive request checks passed.")
        guard CommandLine.arguments.contains("--demo") else { return }
        let login = try await client.login(email: "demo@immich.app", password: "demo")
        let authed = client.with(credential: .accessToken(login.accessToken))
        // Search and ZIP export only; no asset mutations, duplicate reads, or trash calls.
        struct Search: Encodable { let size = 100; let withExif = true }
        do {
            let data = try await authed.data(for: authed.request("search/metadata", method: "POST", body: Search()))
            let results = try decoder.decode(SearchResponse.self, from: data)
            let asset = results.assets.items.filter { $0.type == .image }.min { ($0.exifInfo?.fileSizeInByte ?? .max) < ($1.exifInfo?.fileSizeInByte ?? .max) }!
            let info = try await authed.assetsDownloadInfo(ids: [asset.id], album: nil, archiveSize: nil)
            let archive = info.archives.first!
            let delegate = AssetsDownloadProgress { _, _ in }
            let (temp, response) = try await network.download(for: authed.assetsArchiveRequest(archive.assetIds, archiveName: "Assets-Review-Check"), delegate: delegate)
            defer { try? FileManager.default.removeItem(at: temp) }
            assert((response as? HTTPURLResponse)?.statusCode == 200)
            assert(FileManager.default.fileExists(atPath: temp.path), "Async download must retain the file despite the empty delegate callback")
            let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/AssetsReview/download-check.zip")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            defer { try? FileManager.default.removeItem(at: destination) }
            let zip = try Data(contentsOf: destination)
            assert(zip.starts(with: [0x50, 0x4b]))
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-t", destination.path]
            try unzip.run(); unzip.waitUntilExit()
            assert(unzip.terminationStatus == 0)
            print("Demo ZIP: \(zip.count) bytes, suggested filename \(response.suggestedFilename ?? "nil"); returned temp existed and moved successfully; unzip passed; local ZIP removed.")
        } catch {
            try? await authed.send("POST", "auth/logout")
            throw error
        }
        try await authed.send("POST", "auth/logout")
    }
}

