import Foundation
import CryptoKit
import UniformTypeIdentifiers

extension ImmichClient {
    func uploadMediaTypes() async throws -> UploadMediaTypes { try await get("server/media-types") }

    func checkUpload(checksum: String, name: String) async throws -> UploadCheckResponse {
        struct Item: Encodable { let id: String; let checksum: String }
        struct Body: Encodable { let assets: [Item] }
        return try await send("POST", "assets/bulk-upload-check", body: Body(assets: [Item(id: name, checksum: checksum)]))
    }

    func addUploadToAlbum(_ assetID: String, albumID: String) async throws {
        struct Body: Encodable { let ids: [String] }
        let results: [UploadAlbumResult] = try await send("PUT", "albums/\(albumID)/assets", body: Body(ids: [assetID]))
        guard let result = results.first, result.success || result.error == "duplicate" else {
            throw ImmichError.http(400, results.first?.errorMessage ?? "Could not add the imported item to the album.")
        }
    }

    func uploadFile(_ file: URL, checksum: String, legacy: Bool,
                    progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> UploadResponse {
        let preparation = Task.detached { try UploadMultipart.make(file, legacy: legacy) }
        let multipart = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
        defer { try? FileManager.default.removeItem(at: multipart.file) }
        try Task.checkCancellation()
        var request = try request("assets", method: "POST")
        request.timeoutInterval = 3600
        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "x-immich-checksum")
        let (data, response) = try await session.upload(for: request, fromFile: multipart.file, delegate: UploadProgress(progress))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ImmichError.unauthorized(nil) }
            struct Failure: Decodable { let message: String? }
            throw ImmichError.http(http.statusCode, (try? JSONDecoder().decode(Failure.self, from: data))?.message)
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let update: @Sendable (Int64, Int64) -> Void
    init(_ update: @escaping @Sendable (Int64, Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        update(totalBytesSent, totalBytesExpectedToSend)
    }
}

/// A disk-backed multipart body keeps memory bounded even for large videos.
struct UploadMultipart: Sendable {
    let file: URL
    let boundary: String

    static func checksum(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hash = Insecure.SHA1()
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return Data(hash.finalize()).base64EncodedString()
    }

    static func make(_ source: URL, legacy: Bool) throws -> UploadMultipart {
        let boundary = "ImmichGallery-\(UUID().uuidString)"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            func write(_ text: String) throws { try output.write(contentsOf: Data(text.utf8)) }
            let dates = try source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let modified = dates.contentModificationDate ?? dates.creationDate ?? Date()
            let formatter = ISO8601DateFormatter()
            var fields = ["fileCreatedAt": formatter.string(from: dates.creationDate ?? modified),
                          "fileModifiedAt": formatter.string(from: modified), "isFavorite": "false"]
            // v2 requires device identifiers; v3 removed them from the upload DTO.
            if legacy {
                fields["deviceId"] = "ImmichGallery"
                fields["deviceAssetId"] = "mac-\(source.lastPathComponent)-\(modified.timeIntervalSince1970)"
            }
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
            }
            let name = source.lastPathComponent.replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_").replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
            let mime = UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n")
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n")
            return UploadMultipart(file: file, boundary: boundary)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}
