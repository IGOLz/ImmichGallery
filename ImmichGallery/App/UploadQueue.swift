import AppKit
import Foundation
import Observation

@MainActor @Observable
final class UploadQueue {
    struct Item: Identifiable {
        enum State: Hashable {
            case waiting, preparing, uploading, adding, done, duplicate, failed, cancelled
            var title: String {
                switch self {
                case .waiting: String(localized: "Waiting")
                case .preparing: String(localized: "Preparing")
                case .uploading: String(localized: "Uploading")
                case .adding: String(localized: "Adding to album")
                case .done: String(localized: "Imported")
                case .duplicate: String(localized: "Duplicate")
                case .failed: String(localized: "Failed")
                case .cancelled: String(localized: "Cancelled")
                }
            }
        }
        let id = UUID()
        let url: URL
        let albumID: String?
        var state: State = .waiting
        var sent: Int64 = 0
        var total: Int64 = 0
        var error: String?
        var response: UploadResponse?
        var finished: Bool { [.done, .duplicate, .failed, .cancelled].contains(state) }
    }

    private(set) var items: [Item] = []
    private(set) var discovering = false
    private(set) var revision = 0
    var showingProgress = false
    var lastError: String? { didSet { if lastError != nil { showingProgress = true } } }
    private(set) var unreadableCount = 0
    private(set) var unsupportedCount = 0
    private(set) var completed = 0
    private(set) var imported = 0
    private(set) var duplicates = 0
    private(set) var failed = 0
    private(set) var cancelled = 0
    private struct Key: Hashable { let url: URL; let albumID: String? }
    @ObservationIgnored private var indices: [Key: Int] = [:]
    @ObservationIgnored private var pending: [Int] = []
    @ObservationIgnored private var nextPending = 0
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored var onError: (Error) -> Void = { _ in }
    @ObservationIgnored private let client: ImmichClient
    @ObservationIgnored private var workers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var discovery: Task<Void, Never>?
    @ObservationIgnored private let access = UploadFileAccess()
    @ObservationIgnored private var legacy = false
    @ObservationIgnored var onFinished: () -> Void = {}

    init(client: ImmichClient) { self.client = client }
    var isRunning: Bool { discovering || !workers.isEmpty || completed < items.count }
    var summary: String {
        String(localized: "\(imported) imported, \(duplicates) duplicates, \(failed) failed")
    }

    private func transition(_ index: Int, to state: Item.State) {
        func count(_ state: Item.State, _ delta: Int) {
            switch state {
            case .done: imported += delta; completed += delta
            case .duplicate: duplicates += delta; completed += delta
            case .failed: failed += delta; completed += delta
            case .cancelled: cancelled += delta; completed += delta
            default: break
            }
        }
        count(items[index].state, -1)
        items[index].state = state
        count(state, 1)
        if state == .done || state == .duplicate { needsRefresh = true }
    }

    func chooseFiles(albumID: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose photos, videos, or folders to import. Folders include their subfolders.")
        panel.begin { [weak self] result in
            guard result == .OK else { return }
            Task { @MainActor in self?.enqueue(panel.urls, albumID: albumID) }
        }
    }

    func enqueue(_ urls: [URL], albumID: String? = nil) {
        guard !discovering else { lastError = String(localized: "Please wait for the current folder scan to finish, then try again."); return }
        // Keep the original provider URLs alive even when no explicit scope was granted.
        access.roots.append(contentsOf: urls)
        for url in urls where url.startAccessingSecurityScopedResource() { access.urls.append(url) }
        showingProgress = true
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
                unreadableCount += files.unreadableCount
                let extensions = types.extensions
                for file in files.urls {
                    guard extensions.contains("." + file.pathExtension.lowercased()) else { unsupportedCount += 1; continue }
                    let key = Key(url: file, albumID: albumID)
                    if let index = indices[key] {
                        if items[index].state == .cancelled && workers[items[index].id] == nil {
                            transition(index, to: .waiting)
                            items[index].sent = 0
                            items[index].error = nil
                            pending.append(index)
                        }
                        continue
                    }
                    indices[key] = items.count
                    pending.append(items.count)
                    items.append(Item(url: file, albumID: albumID))
                }
                if files.urls.isEmpty && files.unreadableCount == 0 {
                    lastError = String(localized: "No files were found in the selected folders.")
                }
            } catch {
                if !Task.isCancelled { lastError = error.localizedDescription; onError(error) }
            }
            discovering = false
            discovery = nil
            pump()
        }
    }

    struct ScanResult: Sendable {
        var urls: [URL]
        var unreadableCount: Int
    }

    nonisolated static func scan(_ urls: [URL]) throws -> ScanResult {
        var files = Set<URL>()
        var unreadable = Set<URL>()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for url in urls {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: keys) else { unreadable.insert(url); continue }
            if values.isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in unreadable.insert(url); return true }) else {
                    unreadable.insert(url)
                    continue
                }
                for case let file as URL in enumerator {
                    try Task.checkCancellation()
                    guard let info = try? file.resourceValues(forKeys: keys) else { unreadable.insert(file); continue }
                    if info.isRegularFile == true && info.isSymbolicLink != true { files.insert(file.standardizedFileURL) }
                }
            } else if values.isRegularFile == true && values.isSymbolicLink != true {
                files.insert(url.standardizedFileURL)
            }
        }
        // Upload both Live Photo components as the web client does. Server metadata jobs link their content IDs.
        return ScanResult(urls: files.sorted { $0.path < $1.path }, unreadableCount: unreadable.count)
    }

    func cancelAll() {
        discovery?.cancel()
        workers.values.forEach { $0.cancel() }
        for index in items.indices where !items[index].finished { transition(index, to: .cancelled) }
    }

    func retryFailed() {
        guard workers.isEmpty else { return }
        showingProgress = true
        for index in items.indices where items[index].state == .failed || items[index].state == .cancelled {
            transition(index, to: .waiting)
            if workers[items[index].id] == nil { pending.append(index) }
            items[index].error = nil
            items[index].sent = 0
        }
        pump()
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
        indices.removeAll()
        pending.removeAll()
        nextPending = 0
        completed = 0; imported = 0; duplicates = 0; failed = 0; cancelled = 0
        unreadableCount = 0; unsupportedCount = 0
        access.release()
        lastError = nil
    }

    private func pump() {
        while workers.count < 2 && nextPending < pending.count {
            let index = pending[nextPending]
            nextPending += 1
            guard items[index].state == .waiting else { continue }
            transition(index, to: .preparing)
            workers[items[index].id] = Task { await process(index) }
        }
        if !isRunning && needsRefresh {
            needsRefresh = false
            revision += 1
            onFinished()
        }
    }

    private func process(_ index: Int) async {
        let id = items[index].id
        let file = items[index].url
        do {
            try Task.checkCancellation()
            if items[index].response == nil {
                transition(index, to: .preparing)
                let hashing = Task.detached { try UploadMultipart.checksum(file) }
                let checksum = try await withTaskCancellationHandler { try await hashing.value } onCancel: { hashing.cancel() }
                try Task.checkCancellation()
                var existing: UploadResponse?
                do {
                    if let result = try await client.checkUpload(checksum: checksum, name: file.lastPathComponent).results.first,
                       result.action == "reject", let assetID = result.assetId {
                        existing = UploadResponse(id: assetID, status: "duplicate", isTrashed: result.isTrashed)
                    }
                } catch ImmichError.http(404, _) {
                    // Older servers can still deduplicate with the checksum header and upload response.
                }
                if let existing { items[index].response = existing }
                else {
                    items[index].response = try await client.uploadFile(file, checksum: checksum, legacy: legacy) { [weak self] sent, total in
                        Task { @MainActor in
                            guard let self, !Task.isCancelled, self.workers[id]?.isCancelled == false,
                                  self.items[index].state == .preparing || self.items[index].state == .uploading else { return }
                            self.transition(index, to: .uploading)
                            self.items[index].sent = sent
                            self.items[index].total = total
                        }
                    }
                }
            }
            try Task.checkCancellation()
            guard let response = items[index].response else { throw URLError(.cannotParseResponse) }
            if let albumID = items[index].albumID {
                transition(index, to: .adding)
                try await client.addUploadToAlbum(response.id, albumID: albumID)
            }
            try Task.checkCancellation()
            transition(index, to: response.status == "duplicate" ? .duplicate : .done)
        } catch {
            transition(index, to: Task.isCancelled ? .cancelled : .failed)
            if !Task.isCancelled { items[index].error = error.localizedDescription; showingProgress = true; onError(error) }
        }
        workers[id] = nil
        pump()
    }
}

// Balance sandbox access on Clear and when a signed-out queue finishes releasing its tasks.
private final class UploadFileAccess {
    var roots: [URL] = []
    var urls: [URL] = []
    func release() {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        urls.removeAll()
        roots.removeAll()
    }
    deinit { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
}
