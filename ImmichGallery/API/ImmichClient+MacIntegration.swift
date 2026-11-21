import Foundation
import Synchronization
import UniformTypeIdentifiers

/// Preview files remain leased until the panel closes. Drag promises expire after ten minutes.
enum MacTransferCache {
    private struct State {
        var folders: Set<String> = []
        var discardedRoots: Set<String> = []
    }
    private static let state = Mutex(State())
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacIntegration", isDirectory: true)
    /// Locked Folder files, outside `root` so pruning never races them. Removed on lock and at launch.
    static let lockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LockedFolder", isDirectory: true)

    static func create(preview: Bool, root: URL = MacTransferCache.root) throws -> URL {
        let folder = root.appendingPathComponent(preview ? "Previews" : "Drags", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try state.withLock { state in
            guard !state.discardedRoots.contains(root.standardizedFileURL.path) else { throw CancellationError() }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            state.folders.insert(folder.standardizedFileURL.path)
        }
        return folder
    }

    static func release(_ folder: URL, remove: Bool) {
        state.withLock { state in
            if remove { try? FileManager.default.removeItem(at: folder) }
            _ = state.folders.remove(folder.standardizedFileURL.path)
        }
    }

    /// Prevent a completed download from recreating a Locked Folder directory after locking.
    static func discard(root: URL) {
        state.withLock { state in
            let path = root.standardizedFileURL.path
            state.discardedRoots.insert(path)
            state.folders = state.folders.filter { !$0.hasPrefix(path + "/") }
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func prune(root: URL = MacTransferCache.root, now: Date = Date()) {
        state.withLock { state in
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else { return }
            for case let folder as URL in enumerator {
                guard let values = try? folder.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]), values.isDirectory == true else { continue }
                if folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path && ["Drags", "Previews"].contains(folder.lastPathComponent) { continue }
                enumerator.skipDescendants()
                guard !state.folders.contains(folder.standardizedFileURL.path), let date = values.creationDate,
                      date < now.addingTimeInterval(-600) else { continue }
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
}

extension ImmichClient {
    func downloadVideoForPlayback(_ id: String) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        let downloadSession = dedicatedSession(configuration)
        defer { invalidateSession(downloadSession, cancelPending: false) }
        let progress = PlaybackDownloadLimit()
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await download(for: request("assets/\(id)/video/playback"), delegate: progress, session: downloadSession)
        } catch {
            if progress.exceeded.withLock({ $0 }) { throw PlaybackDownloadLimit.tooLarge }
            throw error
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 { throw ImmichError.unauthorized(nil) }
        if status == 407 { throw ImmichError.proxyAuthentication }
        guard status == 200 else { throw ImmichError.http(status ?? 0, nil) }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= PlaybackDownloadLimit.maxBytes else { throw PlaybackDownloadLimit.tooLarge }
        guard let mime = response.mimeType, let type = UTType(mimeType: mime),
              type.conforms(to: .movie), let fileExtension = type.preferredFilenameExtension else {
            throw ImmichError.http(415, String(localized: "This video format cannot be downloaded for proxy playback."))
        }
        try Task.checkCancellation()
        let folder = try MacTransferCache.create(preview: true, root: transferRoot ?? MacTransferCache.root)
        do {
            let destination = folder.appendingPathComponent("Video").appendingPathExtension(fileExtension)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            MacTransferCache.release(folder, remove: true)
            throw error
        }
    }

    func macIntegrationOriginal(_ id: String, preview: Bool = false) async throws -> URL {
        let (temporary, response) = try await download(for: originalRequest(id))
        defer { try? FileManager.default.removeItem(at: temporary) }
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw ImmichError.unauthorized(nil) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ImmichError.http((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        try Task.checkCancellation()
        let folder = try MacTransferCache.create(preview: preview, root: transferRoot ?? MacTransferCache.root)
        do {
            // Content-Disposition supplies the original filename without a second asset-details request.
            let name = ((response.suggestedFilename ?? id) as NSString).lastPathComponent
            let destination = folder.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? id : name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            if !preview { MacTransferCache.release(folder, remove: false) }
            return destination
        } catch {
            MacTransferCache.release(folder, remove: true)
            throw error
        }
    }
}

private final class PlaybackDownloadLimit: NSObject, URLSessionDownloadDelegate, Sendable {
    static let maxBytes: Int64 = 512 * 1024 * 1024
    static var tooLarge: ImmichError {
        .http(413, String(localized: "This video is larger than the 512 MiB limit for proxy playback."))
    }
    let exceeded = Mutex(false)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if max(totalBytesWritten, totalBytesExpectedToWrite) > Self.maxBytes {
            exceeded.withLock { $0 = true }
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
