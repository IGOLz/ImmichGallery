import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers
import WidgetKit

/// Keeps the desktop widgets fresh while the app runs. For every source an installed photo widget
/// shows (featured, favorites, an album, a person, a place, the chosen photos) it saves downscaled
/// JPEGs in the App Group container, plus the albums, people and places to choose from and the
/// library statistics. See docs/Widget.md.
@MainActor @Observable
final class WidgetFeedUpdater {
    static let shared = WidgetFeedUpdater()

    private nonisolated static let poolSize = 24
    private nonisolated static let maxPerMemory = 4
    private nonisolated static let maxChosen = 50
    private nonisolated static let maxPixelSize = 1280
    private nonisolated static let poolStaleAfter: TimeInterval = 6 * 3600
    private nonisolated static let infoStaleAfter: TimeInterval = 3600

    /// Photos the user picked with "Show in Widget", newest first.
    private(set) var chosen: [String] = []

    @ObservationIgnored private weak var services: AccountServices?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activation: NSObjectProtocol?
    /// Pools to rebuild on the next refresh whatever their age.
    @ObservationIgnored private var dirty: Set<String> = []

    private init() {}

    func start(_ services: AccountServices) {
        guard self.services !== services else { return }
        task?.cancel()
        task = nil
        self.services = services
        let account = accountKey(services)
        chosen = UserDefaults.standard.stringArray(forKey: "widgetChosen." + account) ?? []
        // Switching accounts: never leave the previous account's photos on the desktop.
        if let manifest = WidgetFeed.load(), manifest.account != account { removeFeed() }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                Task { @MainActor in WidgetFeedUpdater.shared.refreshIfNeeded() }
            }
            // A click on a widget that waits for photos opens the app, which then fills it.
            activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetFeedUpdater.shared.refreshIfNeeded() }
            }
        }
        refreshIfNeeded()
    }

    /// Signed out: the widgets must not keep showing the previous account's photos.
    func clear() {
        task?.cancel()
        task = nil
        services = nil
        chosen = []
        removeFeed()
    }

    // MARK: Chosen photos

    func isChosen(_ ids: [String]) -> Bool { !ids.isEmpty && ids.allSatisfy(chosen.contains) }

    func setChosen(_ ids: [String], _ on: Bool) {
        guard let services else { return }
        let ids = ids.filter(WidgetFeed.isID)
        chosen.removeAll { ids.contains($0) }
        if on { chosen.insert(contentsOf: ids, at: 0) }
        chosen = Array(chosen.prefix(Self.maxChosen))
        UserDefaults.standard.set(chosen, forKey: "widgetChosen." + accountKey(services))
        dirty.insert(WidgetFeed.Source.chosen.key)
        refreshIfNeeded()
    }

    // MARK: Refreshing

    private func removeFeed() {
        guard let directory = WidgetFeed.directory else { return }
        try? FileManager.default.removeItem(at: directory)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Hashed: an offline legacy account's cache ID contains its credential.
    private func accountKey(_ services: AccountServices) -> String {
        let key = services.client.apiURL.absoluteString + "|" + services.cacheUserID
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func refreshIfNeeded() {
        guard let services, task == nil, WidgetFeed.directory != nil else { return }
        let account = accountKey(services)
        let previous = WidgetFeed.load().flatMap { $0.account == account ? $0 : nil } ?? WidgetFeed.Manifest(account: account)
        let client = services.client
        let chosen = chosen
        let dirty = dirty
        self.dirty = []
        task = Task {
            defer {
                if self.services === services {
                    self.task = nil
                    if !self.dirty.isEmpty { self.refreshIfNeeded() }
                }
            }
            guard let sources = await Self.installedSources() else { return }
            let now = Date()
            func stale(_ date: Date?, _ age: TimeInterval) -> Bool {
                guard let date else { return true }
                return now.timeIntervalSince(date) > age || !Calendar.current.isDate(date, inSameDayAs: now)
            }
            let rebuild = sources.filter { source in
                dirty.contains(source.key) || stale(previous.pools[source.key]?.updated, Self.poolStaleAfter)
            }
            let needsInfo = stale(previous.catalog?.updated, Self.infoStaleAfter) || stale(previous.stats?.updated, Self.infoStaleAfter)
            let dropped = previous.pools.keys.contains { key in !sources.contains { $0.key == key } }
            guard !rebuild.isEmpty || needsInfo || dropped else { return }

            // A chosen-photos change alone reuses the details already saved for unchanged photos.
            let refetchChosen = stale(previous.pools[WidgetFeed.Source.chosen.key]?.updated, Self.poolStaleAfter)
            let (manifest, files) = await Self.build(client: client, previous: previous, sources: sources, rebuild: rebuild,
                                                     refreshInfo: needsInfo, chosen: chosen, refetchChosen: refetchChosen)
            guard !Task.isCancelled, self.services === services else { return }
            do {
                try Self.write(manifest, files: files)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                // Keep what the widgets already show.
            }
        }
    }

    /// Sources shown by the installed photo widgets. Nil when no widget of the app is installed, or
    /// when WidgetKit can't tell (then nothing is rebuilt or dropped this time).
    private static func installedSources() async -> [WidgetFeed.Source]? {
        struct Installed: Sendable { var photoWidgets: Bool; var sources: [WidgetFeed.Source] }
        let installed: Installed? = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                guard case .success(let widgets) = result else { continuation.resume(returning: nil); return }
                let ours = widgets.filter { WidgetFeed.photoKinds.contains($0.kind) || $0.kind == WidgetFeed.libraryKind }
                guard !ours.isEmpty else { continuation.resume(returning: nil); return }
                var sources: [WidgetFeed.Source] = []
                for widget in ours where WidgetFeed.photoKinds.contains(widget.kind) {
                    // Widgets added in 0.3.1 have no configuration and show featured photos.
                    let source = widget.widgetConfigurationIntent(of: PhotoWidgetIntent.self).map(\.feedSource) ?? .featured
                    if let source, !sources.contains(source) { sources.append(source) }
                }
                let photoWidgets = ours.contains { WidgetFeed.photoKinds.contains($0.kind) }
                continuation.resume(returning: Installed(photoWidgets: photoWidgets, sources: sources))
            }
        }
        guard let installed else { return nil }
        guard installed.photoWidgets else { return [] }
        // Plus what the widgets asked for in the last two days: the app can't always resolve an album
        // or person from a configuration, and a widget reloads at least every six hours, so a removed
        // widget's photos are dropped soon after.
        var sources = installed.sources
        for source in WidgetFeed.requested(within: 2 * 86400) where !sources.contains(source) { sources.append(source) }
        return sources
    }

    // MARK: Building the feed

    private struct Candidate: Sendable {
        let assetID: String
        let memoryID: String?
        let caption: String
    }

    private struct AssetInfo: Decodable {
        struct Exif: Decodable { var city: String? }
        let id: String
        var type: String?
        var localDateTime: String?
        var visibility: String?
        var isTrashed: Bool?
        var exifInfo: Exif?

        var usable: Bool { WidgetFeed.isID(id) && visibility != "locked" && isTrashed != true }

        var caption: String {
            let day = localDateTime.flatMap(ImmichDate.parse).map {
                $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
            }
            return [day, exifInfo?.city].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private struct RandomQuery: Encodable {
        let size: Int
        let type = "IMAGE"
        let withExif = true
        var visibility: String? = "timeline"
        var isFavorite: Bool?
        var albumIds: [String]?
        var personIds: [String]?
        var city: String?
    }

    private nonisolated static func build(client: ImmichClient, previous: WidgetFeed.Manifest, sources: [WidgetFeed.Source],
                                          rebuild: [WidgetFeed.Source], refreshInfo: Bool, chosen: [String],
                                          refetchChosen: Bool) async -> (WidgetFeed.Manifest, [String: Data]) {
        var manifest = WidgetFeed.Manifest(account: previous.account)
        manifest.catalog = previous.catalog
        manifest.stats = previous.stats
        if refreshInfo {
            let catalog = try? await catalog(client: client)
            if let catalog { manifest.catalog = catalog }
            if let stats = try? await stats(client: client, albums: catalog?.albums.count) { manifest.stats = stats }
        }

        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: WidgetFeed.imagesURL?.path ?? "")) ?? [])
        var files: [String: Data] = [:]
        for source in sources {
            guard rebuild.contains(source) else {
                if let pool = previous.pools[source.key] { manifest.pools[source.key] = pool }
                continue
            }
            let known = refetchChosen ? [] : previous.pools[source.key]?.photos ?? []
            guard let candidates = try? await candidates(for: source, client: client, chosen: chosen, known: known) else {
                // Offline or server error: keep the photos this widget already shows.
                if let pool = previous.pools[source.key] { manifest.pools[source.key] = pool }
                continue
            }
            let missing = candidates.map(\.assetID).filter { !existing.contains($0 + ".jpg") && files[$0 + ".jpg"] == nil }
            for (id, data) in await download(missing, client: client) { files[id + ".jpg"] = data }
            var photos = candidates.compactMap { candidate -> WidgetFeed.Photo? in
                let file = candidate.assetID + ".jpg"
                guard existing.contains(file) || files[file] != nil else { return nil }
                return WidgetFeed.Photo(assetID: candidate.assetID, memoryID: candidate.memoryID, caption: candidate.caption, file: file)
            }
            // Featured memories lead the rotation; chosen photos keep the user's order; the rest is shuffled.
            if source != .chosen {
                let memoryCount = photos.prefix { $0.memoryID != nil }.count
                photos = Array(photos.prefix(memoryCount)) + photos.dropFirst(memoryCount).shuffled()
            }
            // Every preview failed to download: keep what the widget shows and try again next time.
            if photos.isEmpty, !candidates.isEmpty, let pool = previous.pools[source.key] {
                manifest.pools[source.key] = pool
                continue
            }
            manifest.pools[source.key] = WidgetFeed.Pool(updated: Date(), photos: photos)
        }
        return (manifest, files)
    }

    /// Throws when the server can't be reached, so the caller keeps the previous pool.
    private nonisolated static func candidates(for source: WidgetFeed.Source, client: ImmichClient, chosen: [String],
                                               known: [WidgetFeed.Photo]) async throws -> [Candidate] {
        var query = RandomQuery(size: poolSize + 6)
        var candidates: [Candidate] = []
        switch source {
        case .featured:
            if (try? await client.explorePreferences())?.memories?.enabled == true,
               let memories = try? await client.exploreMemories(page: 1) {
                for memory in memories {
                    let photos = memory.assets.filter { $0.type == .image && !$0.isTrashed && $0.visibility != "locked" && WidgetFeed.isID($0.id) }
                    candidates += photos.prefix(maxPerMemory).map { Candidate(assetID: $0.id, memoryID: memory.id, caption: memory.title) }
                }
            }
            candidates = Array(candidates.prefix(poolSize / 2))
        case .favorites: query.isFavorite = true; query.visibility = nil
        case .album(let id): query.albumIds = [id]; query.visibility = nil
        case .person(let id): query.personIds = [id]
        case .place(let city): query.city = city
        case .chosen:
            // Each new photo's date and place, four at a time. Only photos the server no longer has
            // (404) drop out; any other error keeps the previous pool.
            let saved = Dictionary(known.map { ($0.assetID, $0.caption) }, uniquingKeysWith: { first, _ in first })
            let fetch = chosen.filter { saved[$0] == nil }
            let infos = try await withThrowingTaskGroup(of: (String, AssetInfo?).self) { group in
                var next = 0
                func enqueue() {
                    guard next < fetch.count else { return }
                    let id = fetch[next]
                    next += 1
                    group.addTask {
                        do { return (id, try await client.get("assets/\(id)") as AssetInfo) }
                        catch ImmichError.http(404, _) { return (id, nil) }
                        catch ImmichError.http(400, _) { return (id, nil) }
                    }
                }
                for _ in 0..<4 { enqueue() }
                var infos: [String: AssetInfo] = [:]
                while let (id, info) = try await group.next() {
                    if let info { infos[id] = info }
                    enqueue()
                }
                return infos
            }
            return chosen.compactMap { id in
                if let caption = saved[id] { return Candidate(assetID: id, memoryID: nil, caption: caption) }
                guard let info = infos[id], info.usable else { return nil }
                return Candidate(assetID: id, memoryID: nil, caption: info.caption)
            }
        }
        let random: [AssetInfo] = try await client.send("POST", "search/random", body: query)
        let seen = Set(candidates.map(\.assetID))
        for asset in random where asset.usable && !seen.contains(asset.id) && asset.visibility != "hidden" {
            candidates.append(Candidate(assetID: asset.id, memoryID: nil, caption: asset.caption))
        }
        return Array(candidates.prefix(poolSize))
    }

    /// Previews downscaled to JPEG, four downloads at a time.
    private nonisolated static func download(_ ids: [String], client: ImmichClient) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            var next = 0
            func enqueue() {
                guard next < ids.count else { return }
                let id = ids[next]
                next += 1
                group.addTask {
                    let data = try? await client.data(for: client.thumbnailRequest(id, size: .preview))
                    return (id, data.flatMap(Self.jpeg))
                }
            }
            for _ in 0..<4 { enqueue() }
            var files: [String: Data] = [:]
            while let (id, data) = await group.next() {
                if let data { files[id] = data }
                enqueue()
            }
            return files
        }
    }

    private nonisolated static func catalog(client: ImmichClient) async throws -> WidgetFeed.Catalog {
        typealias Item = WidgetFeed.Catalog.Item
        let albums = try await client.albums()
            .map { Item(id: $0.id, name: $0.albumName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // People in Immich's order (most photos first); unnamed faces can't be told apart in a list.
        let people = ((try? await client.people(page: 1))?.people ?? [])
            .filter { !$0.isHidden && !$0.name.isEmpty }
            .map { Item(id: $0.id, name: $0.name) }
        let cities = Set(((try? await client.exploreCities()) ?? []).compactMap { $0.exifInfo?.city })
        let places = cities.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { Item(id: $0, name: $0) }
        return WidgetFeed.Catalog(updated: Date(), albums: albums, people: people, places: places)
    }

    private nonisolated static func stats(client: ImmichClient, albums albumCount: Int?) async throws -> WidgetFeed.Stats {
        struct Counts: Decodable { let images: Int; let videos: Int }
        struct Storage: Decodable { let diskUseRaw: Int64; let diskSizeRaw: Int64 }
        struct Me: Decodable { var quotaUsageInBytes: Int64? }
        struct People: Decodable { var total: Int? }
        let counts: Counts = try await client.get("assets/statistics")
        async let storage: Storage? = try? client.get("server/storage")
        async let me: Me? = try? client.get("users/me")
        async let people: People? = try? client.get("people", query: ["size": "1", "withHidden": "false"])
        let (disk, user, faces) = await (storage, me, people)
        let albums: Int? = if let albumCount { albumCount } else { try? await client.albums().count }
        return WidgetFeed.Stats(updated: Date(), photos: counts.images, videos: counts.videos, albums: albums ?? 0,
                                people: faces?.total, libraryBytes: user?.quotaUsageInBytes,
                                diskUsed: disk?.diskUseRaw, diskSize: disk?.diskSizeRaw)
    }

    private static func write(_ manifest: WidgetFeed.Manifest, files: [String: Data]) throws {
        guard let directory = WidgetFeed.directory, let manifestURL = WidgetFeed.manifestURL,
              let images = WidgetFeed.imagesURL else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: images.appendingPathComponent(name), options: .atomic) }
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        // Photos no pool uses any more, and files from 0.3.1's layout.
        let used = Set(manifest.pools.values.flatMap { $0.photos.map(\.file) })
        for url in (try? fm.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)) ?? [] where !used.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where ![manifestURL.lastPathComponent, images.lastPathComponent].contains(url.lastPathComponent) {
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
