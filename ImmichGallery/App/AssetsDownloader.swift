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
private final class AssetsDownloadCancellation: NSObject {
    var task: Task<Void, Never>?
    @objc func cancel() { task?.cancel() }
}

@MainActor
enum AssetsDownloader {
    static func start(ids: [String]? = nil, album: String? = nil, session: LibrarySession) {
        guard album != nil || ids?.isEmpty == false else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.prompt = String(localized: "Download ZIP")
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                               styleMask: [.titled], backing: .buffered, defer: false)
        progress.isReleasedWhenClosed = false
        progress.title = String(localized: "Downloading ZIP")
        let label = NSTextField(labelWithString: String(localized: "Preparing archives…"))
        label.frame = NSRect(x: 20, y: 85, width: 360, height: 24)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 60, width: 360, height: 16))
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        progress.contentView?.addSubview(label)
        progress.contentView?.addSubview(bar)
        let cancellation = AssetsDownloadCancellation()
        let cancel = NSButton(title: String(localized: "Cancel"), target: cancellation, action: #selector(AssetsDownloadCancellation.cancel))
        cancel.frame = NSRect(x: 280, y: 15, width: 100, height: 30)
        progress.contentView?.addSubview(cancel)
        progress.center()
        progress.makeKeyAndOrderFront(nil)
        cancellation.task = Task {
            defer { cancellation.task = nil; progress.close(); if scoped { folder.stopAccessingSecurityScopedResource() } }
            var saved: [URL] = []
            do {
                let preferences: AssetsPreferences? = try? await session.client.get("users/me/preferences")
                let info = try await session.client.assetsDownloadInfo(ids: ids, album: album, archiveSize: preferences?.download.archiveSize)
                let timestamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
                let baseName = album == nil ? "Immich-Selection" : "Immich-Album"
                var completedBytes: Int64 = 0
                for (index, archive) in info.archives.enumerated() {
                    try Task.checkCancellation()
                    let part = String(localized: "Part \(index + 1) of \(info.archives.count)")
                    label.stringValue = part
                    let previousBytes = completedBytes
                    let delegate = AssetsDownloadProgress { written, _ in
                        Task { @MainActor in
                            bar.isIndeterminate = info.totalSize <= 0
                            if info.totalSize > 0 { bar.doubleValue = min(100, Double(previousBytes + written) / Double(info.totalSize) * 100) }
                            label.stringValue = String(localized: "\(part) · \(ByteCountFormatter.string(fromByteCount: previousBytes + written, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: info.totalSize, countStyle: .file))")
                        }
                    }
                    let (temp, response) = try await session.client.session.download(for: session.client.assetsArchiveRequest(archive.assetIds, archiveName: "\(baseName)-\(timestamp)-\(index + 1)"), delegate: delegate)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ImmichError.http((response as? HTTPURLResponse)?.statusCode ?? 500, String(localized: "The archive could not be downloaded."))
                    }
                    let suggested = response.suggestedFilename.map { URL(fileURLWithPath: $0).lastPathComponent }
                    let name = suggested.flatMap { $0.lowercased().hasSuffix(".zip") ? $0 : nil } ?? "\(baseName)-\(timestamp)-\(index + 1).zip"
                    var destination = folder.appendingPathComponent(name)
                    var suffix = 2
                    while FileManager.default.fileExists(atPath: destination.path) {
                        destination = folder.appendingPathComponent("\(String(name.dropLast(4))) (\(suffix)).zip")
                        suffix += 1
                    }
                    try FileManager.default.moveItem(at: temp, to: destination)
                    saved.append(destination)
                    completedBytes += archive.size
                }
                NSWorkspace.shared.activateFileViewerSelecting(saved)
            } catch {
                if Task.isCancelled || error.isCancellation {
                    // URLSession removes its unfinished temporary file; completed parts are also removed on cancel.
                    for file in saved { try? FileManager.default.removeItem(at: file) }
                    return
                }
                session.handle(error)
                let alert = NSAlert()
                alert.messageText = String(localized: "Download Failed")
                alert.informativeText = error.localizedDescription + (saved.isEmpty ? "" : String(localized: " Already completed ZIP parts remain in the chosen folder."))
                alert.runModal()
            }
        }
    }
}
