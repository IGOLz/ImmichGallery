import AppKit

/// "Export Unmodified Original" — downloads originals into a folder the user picks.
@MainActor
enum Exporter {
    static func exportOriginals(_ ids: [String], session: LibrarySession?) {
        guard let session, !ids.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Originals")
        panel.message = String(localized: "Choose a folder for \(ids.count) original files.")
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        Task {
            var saved: [URL] = []
            var failures = 0
            for id in ids {
                do {
                    let asset = try await session.client.asset(id)
                    let (temp, response) = try await session.client.session.download(for: session.client.originalRequest(id))
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { failures += 1; continue }
                    let destination = uniqueURL(in: folder, name: asset.originalFileName)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    saved.append(destination)
                } catch {
                    session.handle(error)
                    failures += 1
                }
            }
            if !saved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(saved) }
            if failures > 0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "\(failures) items couldn't be exported.")
                alert.runModal()
            }
        }
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
