import Foundation
import Synchronization

/// Preview files remain leased until the panel closes. Drag promises expire after ten minutes.
enum MacTransferCache {
    private static let active = Mutex<Set<String>>([])
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacIntegration", isDirectory: true)
    /// Locked Folder files, outside `root` so pruning never races them. Removed on lock and at launch.
    static let lockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LockedFolder", isDirectory: true)

    static func create(preview: Bool, root: URL = MacTransferCache.root) throws -> URL {
        let folder = root.appendingPathComponent(preview ? "Previews" : "Drags", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try active.withLock { folders in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            folders.insert(folder.standardizedFileURL.path)
        }
        return folder
    }

    static func release(_ folder: URL, remove: Bool) {
        active.withLock { folders in
            if remove { try? FileManager.default.removeItem(at: folder) }
            _ = folders.remove(folder.standardizedFileURL.path)
        }
    }

    static func prune(root: URL = MacTransferCache.root, now: Date = Date()) {
        active.withLock { folders in
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else { return }
            for case let folder as URL in enumerator {
                guard let values = try? folder.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]), values.isDirectory == true else { continue }
                if folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path && ["Drags", "Previews"].contains(folder.lastPathComponent) { continue }
                enumerator.skipDescendants()
                guard !folders.contains(folder.standardizedFileURL.path), let date = values.creationDate,
                      date < now.addingTimeInterval(-600) else { continue }
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
}

extension ImmichClient {
    func macIntegrationOriginal(_ id: String, preview: Bool = false) async throws -> URL {
        let (temporary, response) = try await session.download(for: originalRequest(id))
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
