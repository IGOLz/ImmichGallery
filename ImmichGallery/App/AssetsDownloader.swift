import AppKit
import Foundation

/// URLSession writes the archive to a temporary file, keeping ZIP contents out of memory.
final class AssetsDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let update: @Sendable (Int64, Int64) -> Void
    init(update: @escaping @Sendable (Int64, Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        update(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
enum AssetsDownloader {
    static func start(ids: [String]? = nil, album: String? = nil, session: LibrarySession) {
        guard album != nil || ids?.isEmpty == false else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.prompt = "Download ZIP"
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 130),
                               styleMask: [.titled], backing: .buffered, defer: false)
        progress.isReleasedWhenClosed = false
        progress.title = "Downloading ZIP"
        let label = NSTextField(labelWithString: "Preparing archives…")
        label.frame = NSRect(x: 20, y: 85, width: 360, height: 24)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 60, width: 360, height: 16))
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        progress.contentView?.addSubview(label)
        progress.contentView?.addSubview(bar)
        progress.center()
        progress.makeKeyAndOrderFront(nil)
        Task {
            defer { progress.close(); if scoped { folder.stopAccessingSecurityScopedResource() } }
            var saved: [URL] = []
            do {
                let preferences: AssetsPreferences? = try? await session.client.get("users/me/preferences")
                let info = try await session.client.assetsDownloadInfo(ids: ids, album: album, archiveSize: preferences?.download.archiveSize)
                for (index, archive) in info.archives.enumerated() {
                    let part = "Part \(index + 1) of \(info.archives.count)"
                    label.stringValue = part
                    let delegate = AssetsDownloadProgress { written, expected in
                        Task { @MainActor in
                            bar.isIndeterminate = expected <= 0
                            if expected > 0 { bar.doubleValue = Double(written) / Double(expected) * 100 }
                            label.stringValue = "\(part) · \(ByteCountFormatter.string(fromByteCount: written, countStyle: .file))"
                        }
                    }
                    let (temp, response) = try await session.client.session.download(for: session.client.assetsArchiveRequest(archive.assetIds), delegate: delegate)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ImmichError.http((response as? HTTPURLResponse)?.statusCode ?? 500, "The archive could not be downloaded.")
                    }
                    // A unique name avoids replacing an existing export.
                    let name = "Immich-\(UUID().uuidString.prefix(8))-\(index + 1).zip"
                    let destination = folder.appendingPathComponent(name)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    saved.append(destination)
                }
                NSWorkspace.shared.activateFileViewerSelecting(saved)
            } catch {
                session.handle(error)
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = error.localizedDescription + (saved.isEmpty ? "" : " Already completed ZIP parts remain in the chosen folder.")
                alert.runModal()
            }
        }
    }
}
