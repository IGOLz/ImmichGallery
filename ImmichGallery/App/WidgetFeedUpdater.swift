import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Keeps the desktop widget's photos fresh while the app runs: today's memories first, then
/// random photos from the timeline. Photos are downscaled JPEGs in the App Group container.
@MainActor
final class WidgetFeedUpdater {
    static let shared = WidgetFeedUpdater()

    private nonisolated static let maxPhotos = 24
    private nonisolated static let maxPerMemory = 4
    private nonisolated static let maxPixelSize = 1280
    private static let staleAfter: TimeInterval = 6 * 3600

    private weak var services: AccountServices?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var activation: NSObjectProtocol?

    private init() {}

    func start(_ services: AccountServices) {
        guard self.services !== services else { return }
        task?.cancel()
        task = nil
        self.services = services
        // Switching accounts: never leave the previous account's photos on the desktop.
        if let manifest = WidgetFeed.load(), manifest.account != accountKey(services) { removeFeed() }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                Task { @MainActor in WidgetFeedUpdater.shared.refreshIfNeeded() }
            }
            // A click on an empty widget opens the app, which then fills it.
            activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetFeedUpdater.shared.refreshIfNeeded() }
            }
        }
        refreshIfNeeded()
    }

    /// Signed out: the widget must not keep showing the previous account's photos.
    func clear() {
        task?.cancel()
        task = nil
        services = nil
        removeFeed()
    }

    private func removeFeed() {
        guard let directory = WidgetFeed.directory else { return }
        try? FileManager.default.removeItem(at: directory)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
    }

    /// Hashed: an offline legacy account's cache ID contains its credential.
    private func accountKey(_ services: AccountServices) -> String {
        let key = services.client.apiURL.absoluteString + "|" + services.cacheUserID
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func refreshIfNeeded() {
        guard let services, task == nil, WidgetFeed.directory != nil else { return }
        let account = accountKey(services)
        if let manifest = WidgetFeed.load(), manifest.account == account, !manifest.photos.isEmpty,
           Calendar.current.isDateInToday(manifest.updated),
           Date().timeIntervalSince(manifest.updated) < Self.staleAfter { return }
        let client = services.client
        task = Task {
            defer { if self.services === services { self.task = nil } }
            guard await Self.widgetInstalled() else { return }
            do {
                let (manifest, files) = try await Self.build(client: client, account: account)
                guard !Task.isCancelled, self.services === services else { return }
                try Self.write(manifest, files: files)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
            } catch {
                // Offline or server error: keep the photos already on the widget.
            }
        }
    }

    private static func widgetInstalled() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let installed = (try? result.get())?.contains { $0.kind == WidgetFeed.kind } ?? true
                continuation.resume(returning: installed)
            }
        }
    }

    // MARK: Building the feed

    private struct Candidate: Sendable {
        let assetID: String
        let memoryID: String?
        let caption: String
    }

    private struct RandomAsset: Decodable {
        struct Exif: Decodable { var city: String? }
        let id: String
        let localDateTime: String
        var visibility: String?
        var exifInfo: Exif?
    }

    private nonisolated static func build(client: ImmichClient, account: String) async throws -> (WidgetFeed.Manifest, [String: Data]) {
        var candidates: [Candidate] = []
        if (try? await client.explorePreferences())?.memories?.enabled == true,
           let memories = try? await client.exploreMemories(page: 1) {
            for memory in memories {
                let photos = memory.assets.filter { $0.type == .image && !$0.isTrashed && $0.visibility != "locked" && WidgetFeed.isID($0.id) }
                candidates += photos.prefix(maxPerMemory).map { Candidate(assetID: $0.id, memoryID: memory.id, caption: memory.title) }
            }
        }
        candidates = Array(candidates.prefix(maxPhotos / 2))

        struct RandomQuery: Encodable {
            let size: Int
            let type = "IMAGE"
            let visibility = "timeline"
            let withExif = true
        }
        let random: [RandomAsset] = try await client.send("POST", "search/random", body: RandomQuery(size: maxPhotos + 6))
        let seen = Set(candidates.map(\.assetID))
        for asset in random where !seen.contains(asset.id) && asset.visibility != "locked" && WidgetFeed.isID(asset.id) {
            let day = ImmichDate.parse(asset.localDateTime).map {
                $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
            }
            let caption = [day, asset.exifInfo?.city].compactMap { $0 }.joined(separator: " · ")
            candidates.append(Candidate(assetID: asset.id, memoryID: nil, caption: caption))
        }
        candidates = Array(candidates.prefix(maxPhotos))

        // Download a few at a time, keeping the original order.
        var files: [Int: Data] = [:]
        try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
            var next = 0
            func enqueue() {
                guard next < candidates.count else { return }
                let index = next, id = candidates[index].assetID
                next += 1
                group.addTask {
                    let data = try? await client.data(for: client.thumbnailRequest(id, size: .preview))
                    return (index, data.flatMap(Self.jpeg))
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (index, data) = try await group.next() {
                try Task.checkCancellation()
                if let data { files[index] = data }
                enqueue()
            }
        }

        var photos: [WidgetFeed.Photo] = []
        var payload: [String: Data] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard let data = files[index] else { continue }
            let file = candidate.assetID + ".jpg"
            payload[file] = data
            photos.append(.init(assetID: candidate.assetID, memoryID: candidate.memoryID, caption: candidate.caption, file: file))
        }
        // Memories lead the rotation; the rest is shuffled so each day looks different.
        let memoryCount = photos.prefix { $0.memoryID != nil }.count
        photos = Array(photos.prefix(memoryCount)) + photos.dropFirst(memoryCount).shuffled()
        return (WidgetFeed.Manifest(account: account, updated: Date(), photos: photos), payload)
    }

    private static func write(_ manifest: WidgetFeed.Manifest, files: [String: Data]) throws {
        guard let directory = WidgetFeed.directory, let manifestURL = WidgetFeed.manifestURL else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        let keep = Set(manifest.photos.map(\.file) + [manifestURL.lastPathComponent])
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where !keep.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    /// Downscales a server preview (JPEG or WebP) to a small JPEG the widget can decode cheaply.
    private nonisolated static func jpeg(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
