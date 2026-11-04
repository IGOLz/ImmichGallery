import Foundation

extension ImmichClient {
    /// Keep promised files available for receiving apps, then expire them on a later transfer.
    private static func macIntegrationPruneTransfers() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacIntegration", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for directory in directories {
            if let date = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate,
               date < Date().addingTimeInterval(-86_400) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    /// A private temporary directory per transfer avoids collisions and cross-account reuse.
    func macIntegrationOriginal(_ id: String) async throws -> URL {
        Self.macIntegrationPruneTransfers()
        let asset = try await asset(id)
        let (temporary, response) = try await session.download(for: originalRequest(id))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ImmichError.http((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacIntegration", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Server-provided names must never escape the transfer directory.
        let name = (asset.originalFileName as NSString).lastPathComponent
        let destination = folder.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? UUID().uuidString : name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
