import AppKit
import Foundation
import Observation

@MainActor @Observable
final class UploadQueue {
    struct Item: Identifiable {
        enum State: String { case waiting = "Waiting", preparing = "Preparing", uploading = "Uploading", adding = "Adding to album", done = "Imported", duplicate = "Duplicate", failed = "Failed", cancelled = "Cancelled", skipped = "Unsupported type" }
        let id = UUID()
        let url: URL
        let albumID: String?
        var state: State = .waiting
        var sent: Int64 = 0
        var total: Int64 = 0
        var error: String?
        var response: UploadResponse?
        var finished: Bool { [.done, .duplicate, .failed, .cancelled, .skipped].contains(state) }
    }

    private(set) var items: [Item] = []
    private(set) var discovering = false
    private(set) var revision = 0
    var lastError: String?
    @ObservationIgnored private let client: ImmichClient
    @ObservationIgnored private var workers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var discovery: Task<Void, Never>?
    @ObservationIgnored private let access = UploadFileAccess()
    @ObservationIgnored private var legacy = false
    @ObservationIgnored var onFinished: () -> Void = {}

    init(client: ImmichClient) { self.client = client }
    var isRunning: Bool { discovering || !workers.isEmpty || items.contains { !$0.finished } }
    var completed: Int { items.filter(\.finished).count }
    var summary: String {
        "\(items.filter { $0.state == .done }.count) imported, \(items.filter { $0.state == .duplicate }.count) duplicates, \(items.filter { $0.state == .failed }.count) failed"
    }

    func chooseFiles(albumID: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Choose photos, videos, or folders to import. Folders include their subfolders."
        panel.begin { [weak self] result in
            guard result == .OK else { return }
            Task { @MainActor in self?.enqueue(panel.urls, albumID: albumID) }
        }
    }

    func enqueue(_ urls: [URL], albumID: String? = nil) {
        guard !discovering else { lastError = "Please wait for the current folder scan to finish, then try again."; return }
        for url in urls where url.startAccessingSecurityScopedResource() { access.urls.append(url) }
        discovering = true
        lastError = nil
        discovery = Task {
            do {
                let types = try await client.uploadMediaTypes()
                let version = try await client.serverVersion()
                legacy = version.major < 3
                let scan = Task.detached { try Self.scan(urls) }
                let files = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
                try Task.checkCancellation()
                for file in files {
                    guard !items.contains(where: { $0.url == file && $0.albumID == albumID && $0.state != .cancelled }) else { continue }
                    var item = Item(url: file, albumID: albumID)
                    if !types.extensions.contains("." + file.pathExtension.lowercased()) { item.state = .skipped }
                    items.append(item)
                }
                if files.isEmpty { lastError = "No files were found in the selected folders." }
            } catch {
                if !Task.isCancelled { lastError = error.localizedDescription }
            }
            discovering = false
            discovery = nil
            pump()
        }
    }

    nonisolated static func scan(_ urls: [URL]) throws -> [URL] {
        var files = Set<URL>()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for url in urls {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                var scanError: Error?
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return false }) else {
                    throw CocoaError(.fileReadNoPermission)
                }
                for case let file as URL in enumerator {
                    try Task.checkCancellation()
                    let info = try file.resourceValues(forKeys: keys)
                    if info.isRegularFile == true && info.isSymbolicLink != true { files.insert(file.standardizedFileURL) }
                }
                if let scanError { throw scanError }
            } else if values.isRegularFile == true && values.isSymbolicLink != true {
                files.insert(url.standardizedFileURL)
            }
        }
        // Upload both Live Photo components as the web client does. Server metadata jobs link their content IDs.
        return files.sorted { $0.path < $1.path }
    }

    func cancelAll() {
        discovery?.cancel()
        workers.values.forEach { $0.cancel() }
        for index in items.indices where !items[index].finished { items[index].state = .cancelled }
    }

    func retryFailed() {
        for index in items.indices where items[index].state == .failed || items[index].state == .cancelled {
            items[index].state = .waiting
            items[index].error = nil
            items[index].sent = 0
        }
        pump()
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
        access.release()
        lastError = nil
    }

    private func pump() {
        for item in items where item.state == .waiting && workers[item.id] == nil {
            guard workers.count < 2 else { break }
            workers[item.id] = Task { await process(item.id) }
        }
        if !isRunning {
            revision += 1
            onFinished()
        }
    }

    private func process(_ id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let file = items[index].url
        do {
            try Task.checkCancellation()
            if items[index].response == nil {
                items[index].state = .preparing
                let hashing = Task.detached { try UploadMultipart.checksum(file) }
                let checksum = try await withTaskCancellationHandler { try await hashing.value } onCancel: { hashing.cancel() }
                try Task.checkCancellation()
                var existing: UploadResponse?
                do {
                    if let result = try await client.checkUpload(checksum: checksum, name: file.lastPathComponent).results.first,
                       result.action == "reject", let assetID = result.assetId {
                        if result.isTrashed == true { throw ImmichError.http(409, "This duplicate is in Recently Deleted. Restore it before importing.") }
                        existing = UploadResponse(id: assetID, status: "duplicate")
                    }
                } catch ImmichError.http(404, _) {
                    // Older servers can still deduplicate with the checksum header and upload response.
                }
                if let existing { items[index].response = existing }
                else {
                    items[index].state = .uploading
                    items[index].response = try await client.uploadFile(file, checksum: checksum, legacy: legacy) { [weak self] sent, total in
                        Task { @MainActor in
                            guard let self, let i = self.items.firstIndex(where: { $0.id == id }), self.items[i].state == .uploading else { return }
                            self.items[i].sent = sent
                            self.items[i].total = total
                        }
                    }
                }
            }
            try Task.checkCancellation()
            guard let response = items[index].response else { throw URLError(.cannotParseResponse) }
            if let albumID = items[index].albumID {
                items[index].state = .adding
                try await client.addUploadToAlbum(response.id, albumID: albumID)
            }
            items[index].state = response.status == "duplicate" ? .duplicate : .done
        } catch {
            items[index].state = Task.isCancelled ? .cancelled : .failed
            if !Task.isCancelled { items[index].error = error.localizedDescription }
        }
        workers[id] = nil
        pump()
    }
}

// Balance sandbox access on Clear and when a signed-out queue finishes releasing its tasks.
private final class UploadFileAccess {
    var urls: [URL] = []
    func release() {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        urls.removeAll()
    }
    deinit { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
}
