import AppKit
import Foundation
import Observation

/// What a grid shows.
enum GridSource: Hashable {
    case library, favorites, videos, archive, trash
    case largeFiles, geolocation // Assets
    case album(String)
    case partner(String) // Sharing
    case person(String)
    case search(String)
    case filteredSearch(SearchQuery) // Search

    case explore(ExploreSource) // Explore

    var isPartner: Bool { if case .partner = self { true } else { false } }

    var excludesArchived: Bool {
        switch self {
        case .library, .videos, .geolocation, .largeFiles, .person, .explore(.city), .explore(.folder): true
        case .explore(.map(let query)): !query.archived
        default: false
        }
    }

    var timelineQuery: TimelineQuery? {
        switch self {
        case .library: TimelineQuery(withPartners: true)
        case .geolocation: TimelineQuery(withPartners: false)
        case .favorites: TimelineQuery(visibility: nil, isFavorite: true)
        case .archive: TimelineQuery(visibility: "archive")
        case .trash: TimelineQuery(visibility: nil, isTrashed: true)
        case .album(let id): TimelineQuery(visibility: nil, albumId: id)
        case .partner(let id): TimelineQuery(userId: id) // Sharing
        case .person(let id): TimelineQuery(personId: id)
        case .explore(.tag(let id)): TimelineQuery(visibility: nil, tagId: id)
        case .explore(.map(let query)): query.timeline
        case .explore: nil
        case .videos, .search, .filteredSearch, .largeFiles: nil
        }
    }
}

extension GridSource {
    /// Grid pages with view options (GridArrangement).
    var gridPage: GridPage? {
        switch self {
        case .library: .library
        case .favorites: .favorites
        case .videos: .videos
        case .archive: .archive
        case .largeFiles: .largeFiles // Assets
        case .partner: .partner // Sharing
        case .person: .person
        case .explore(.tag): .tag // Explore
        default: nil
        }
    }
}

/// Lightweight asset used by grids and the viewer.
struct AssetItem: Identifiable, Hashable, Sendable {
    let id: String
    let ownerId: String?
    let isVideo: Bool
    var isFavorite: Bool
    var isTrashed: Bool
    let thumbhash: String?
    let ratio: Double
    let durationMS: Int?
    let date: Date?
    let livePhotoVideoID: String?
    let stackCount: Int?
    var fileSizeInBytes: Int64? = nil

    init(_ r: AssetResponse) {
        id = r.id
        ownerId = r.ownerId
        isVideo = r.type == .video
        isFavorite = r.isFavorite
        isTrashed = r.isTrashed
        thumbhash = r.thumbhash
        if let w = r.width, let h = r.height, h > 0 { ratio = Double(w) / Double(h) } else { ratio = 1 }
        durationMS = r.duration?.milliseconds
        date = ImmichDate.parse(r.localDateTime)
        livePhotoVideoID = r.livePhotoVideoId
        stackCount = r.stack?.assetCount
        fileSizeInBytes = r.exifInfo?.fileSizeInByte
    }

    static func from(_ c: TimeBucketAssets) -> [AssetItem] {
        c.id.indices.filter { c.visibility?.indices.contains($0) != true || c.visibility?[$0] != "locked" }.map { i in
            AssetItem(
                id: c.id[i], ownerId: c.ownerId.flatMap { $0.indices.contains(i) ? $0[i] : nil }, isVideo: !c.isImage[i], isFavorite: c.isFavorite[i], isTrashed: c.isTrashed[i],
                thumbhash: c.thumbhash[i], ratio: c.ratio[i] ?? 1, durationMS: c.duration[i]?.milliseconds,
                date: ImmichDate.parse(c.fileCreatedAt[i]), livePhotoVideoID: c.livePhotoVideoId[i],
                stackCount: c.stack?[i].flatMap { $0.count > 1 ? Int($0[1]) : nil })
        }
    }

    private init(id: String, ownerId: String?, isVideo: Bool, isFavorite: Bool, isTrashed: Bool, thumbhash: String?, ratio: Double,
                 durationMS: Int?, date: Date?, livePhotoVideoID: String?, stackCount: Int?) {
        self.ownerId = ownerId
        self.id = id; self.isVideo = isVideo; self.isFavorite = isFavorite; self.isTrashed = isTrashed
        self.thumbhash = thumbhash; self.ratio = ratio; self.durationMS = durationMS; self.date = date
        self.livePhotoVideoID = livePhotoVideoID; self.stackCount = stackCount
    }
}

struct GridSection: Identifiable {
    let id: String
    let title: String?
    var count: Int
    /// `nil` until the bucket has been fetched.
    var assets: [AssetItem]?
}

@MainActor @Observable
final class AssetGridModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    let source: GridSource
    @ObservationIgnored private weak var session: LibrarySession?

    var albumOrder = "desc" // Albums
    /// The page's view options, read from its saved settings on every reload.
    private(set) var arrangement: GridArrangement?
    private(set) var sections: [GridSection] = []
    private(set) var state: LoadState = .idle
    private(set) var searchResultsLoaded = 0
    @ObservationIgnored private var sortedSmartResults: [AssetResponse]?
    var selection: Set<String> = []
    var viewerID: String?
    var viewerScrollTarget: String? // Viewer
    func viewerLoadSection(_ section: Int) async {
        guard sections.indices.contains(section), sections[section].assets == nil else { return }
        await loadSection(id: sections[section].id).value
    }

    func viewerAllItems() async throws -> [AssetItem] {
        for i in sections.indices { await viewerLoadSection(i) }
        while isPaged, nextPage != nil { try await fetchNextPage() }
        return sections.flatMap { $0.assets ?? [] }
    }

    @ObservationIgnored private var anchorID: String?
    @ObservationIgnored private var index: [String: (section: Int, item: Int)] = [:]
    @ObservationIgnored private var sectionTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isStale = false
    // Paged sources (search, videos)
    @ObservationIgnored private var nextPage: ImmichClient.SearchPage?
    @ObservationIgnored private var pageFailed = false
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    /// The first load, shared so a second caller waits for it instead of returning early (Widget).
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(source: GridSource, session: LibrarySession, reusing previous: AssetGridModel? = nil) {
        self.source = source
        self.session = session
        if case .filteredSearch(var query) = source, query.sort != .automatic,
           case .filteredSearch(var oldQuery) = previous?.source, oldQuery.sort != .automatic,
           previous?.isStale == false, let items = previous?.sortedSmartResults {
            let order = query.sort
            query.sort = .automatic; oldQuery.sort = .automatic
            if query == oldQuery {
                sortedSmartResults = items
                append(ImmichClient.sortSearchAssets(items, order: order).items.map(AssetItem.init))
                state = .loaded
            }
        }
    }

    var totalCount: Int { sections.reduce(0) { $0 + $1.count } }

    private var dateAdded: Bool { GridArrangement.supportsDateAdded(session?.version) }

    /// The source's timeline filters with the page's view options applied.
    private var timelineQuery: TimelineQuery? {
        guard let query = source.timelineQuery else { return nil }
        return arrangement.map { $0.applied(to: query, dateAdded: dateAdded) } ?? query
    }

    /// The ID prefix ("2026-11") of the section that holds an asset, following the view options.
    func sectionMonth(of asset: AssetResponse) -> Substring? {
        (arrangement ?? GridArrangement()).month(localDateTime: asset.localDateTime, createdAt: asset.createdAt, dateAdded: dateAdded)
    }

    var isPaged: Bool { source.timelineQuery == nil }
    var showsSectionHeaders: Bool {
        switch source { case .search, .filteredSearch, .largeFiles: false; default: true }
    }

    func asset(_ section: Int, _ item: Int) -> AssetItem? {
        guard sections.indices.contains(section), let assets = sections[section].assets,
              assets.indices.contains(item) else { return nil }
        return assets[item]
    }

    func item(_ id: String) -> AssetItem? {
        guard let pos = index[id] else { return nil }
        return asset(pos.section, pos.item)
    }

    func canMutate(_ ids: [String]) -> Bool {
        guard !source.isPartner, source != .trash, !ids.isEmpty, let userID = session?.user?.id else { return false }
        return ids.allSatisfy { item($0)?.ownerId == userID }
    }

    func canDelete(_ ids: [String]) -> Bool {
        guard !source.isPartner, !ids.isEmpty, let userID = session?.user?.id else { return false }
        return ids.allSatisfy { item($0)?.ownerId == userID }
    }

    var selectedItems: [AssetItem] { selection.compactMap(item) }

    // MARK: Loading

    func loadIfNeeded() async {
        if let loadTask { await loadTask.value }
        // View options changed while this grid was off screen.
        let arrangementChanged = arrangement != source.gridPage.map { GridArrangement(page: $0) }
        guard state == .idle || isStale || arrangementChanged else { return }
        await reload()
    }

    // Explore: remove sensitive items immediately from every cached grid and viewer.
    func exploreRemove(_ ids: Set<String>) {
        if let viewerID, ids.contains(viewerID) { self.viewerID = nil }
        selection.subtract(ids)
        for i in sections.indices {
            sections[i].assets?.removeAll { ids.contains($0.id) }
            if let assets = sections[i].assets { sections[i].count = assets.count }
        }
        rebuildIndex()
        markStale()
    }

    func markStale() { isStale = true }

    func cancelLoading() {
        loadTask?.cancel()
        pageTask?.cancel()
        sectionTasks.values.forEach { $0.cancel() }
    }

    func reload() async {
        if let previous = loadTask {
            previous.cancel()
            await previous.value
        }
        let task = Task { await performReload() }
        loadTask = task
        await task.value
        if loadTask == task { loadTask = nil }
    }

    private func performReload() async {
        guard let session else { return }
        isStale = false
        sortedSmartResults = nil
        searchResultsLoaded = 0
        pageFailed = false
        sectionTasks.values.forEach { $0.cancel() }
        sectionTasks = [:]
        pageTask?.cancel()
        pageTask = nil
        if sections.isEmpty { state = .loading }
        arrangement = source.gridPage.map { GridArrangement(page: $0) }
        do {
            if let query = timelineQuery {
                var buckets = try await source.albumID != nil
                    ? session.client.albumTimeBuckets(query, order: albumOrder)
                    : session.client.timeBuckets(query)
                if case .explore(.map(let map)) = source {
                    buckets.removeAll { !map.includesMonth(start: ImmichDate.parse($0.timeBucket)) }
                }
                sections = buckets.map {
                    GridSection(id: $0.timeBucket, title: ImmichDate.monthTitle($0.timeBucket), count: $0.count)
                }
                rebuildIndex()
                state = .loaded
                // Load the first screenful right away.
                for i in sections.indices.prefix(2) { ensureLoaded(i) }
            } else {
                sections = []
                nextPage = .init(page: 1)
                rebuildIndex()
                try await fetchNextPage()
                state = .loaded
            }
        } catch {
            if error.isCancellation {
                if sections.isEmpty { state = .idle }
                return
            }
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    /// Called as cells scroll into view.
    func cellAppeared(section: Int, item: Int) {
        if isPaged {
            if section == sections.count - 1, item >= sections[section].count - 60 { loadNextPage() }
        } else {
            ensureLoaded(section)
            if item > sections[section].count - 30 { ensureLoaded(section + 1) }
        }
    }

    func ensureLoaded(_ section: Int) {
        guard sections.indices.contains(section), sections[section].assets == nil else { return }
        _ = loadSection(id: sections[section].id)
    }

    @discardableResult
    private func loadSection(id: String) -> Task<Void, Never> {
        if let task = sectionTasks[id] { return task }
        let task = Task { [weak self] in
            guard let self, let session, let query = timelineQuery else { return }
            do {
                let columns = try await source.albumID != nil
                    ? session.client.albumTimeBucket(id, query, order: albumOrder)
                    : session.client.timeBucket(id, query)
                guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
                var assets = AssetItem.from(columns).filter { self.source != .geolocation || (session.user?.id != nil && $0.ownerId == session.user?.id) }
                if case .explore(.map(let query)) = source { assets.removeAll { !query.includes($0.date) } }
                sections[i].assets = assets
                sections[i].count = assets.count
                rebuildIndex()
            } catch {
                session.handle(error)
                sectionTasks[id] = nil // allow retry on next appearance
            }
        }
        sectionTasks[id] = task
        return task
    }

    private func loadNextPage() {
        guard !pageFailed, pageTask == nil, nextPage != nil else { return }
        pageTask = Task { [weak self] in
            guard let self else { return }
            do { try await fetchNextPage() }
            catch { if !error.isCancellation { pageFailed = true; report(error) } }
            pageTask = nil
        }
    }

    private func fetchNextPage() async throws {
        guard let session, let page = nextPage else { return }
        let result: SearchResponse.Assets
        switch source {
        case .largeFiles:
            let assets = try await session.client.assetsLargeFiles(type: arrangement?.assetType, isFavorite: arrangement?.isFavorite)
            nextPage = nil
            append(assets.filter { $0.visibility != "locked" }.map(AssetItem.init))
            return
        case .search(let text):
            if session.features.smartSearch {
                result = try await session.client.smartSearch(text, page: page.page ?? 1)
            } else {
                result = try await session.client.metadataSearch(fileName: text, page: page)
            }
        case .filteredSearch(let query):
            result = try await session.client.advancedSearch(query, smartEnabled: session.features.smartSearch, page: page) { [weak self] count in
                self?.searchResultsLoaded = count
            }
            if query.mode == .context, session.features.smartSearch,
               !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               query.sort != .automatic, result.nextPage == nil, result.nextCursor == nil {
                sortedSmartResults = result.items.filter { $0.visibility != "locked" }
            }
        case .explore(let source):
            result = try await session.client.exploreAssets(source, page: page)
        case .videos:
            // Live Photo motion components are hidden and have no standalone thumbnails.
            result = try await session.client.metadataSearch(type: .video, visibility: "timeline", isFavorite: arrangement?.isFavorite,
                                                             order: (arrangement?.order ?? .newestFirst).rawValue, page: page)
        default:
            return
        }
        if let cursor = result.nextCursor {
            nextPage = .init(cursor: cursor)
        } else if let next = result.nextPage.flatMap(Int.init) {
            nextPage = .init(page: next)
        } else {
            nextPage = nil
        }
        append(result.items.filter { $0.visibility != "locked" }.map(AssetItem.init))
        // A page containing only locked results must not strand the pagination trigger.
        if result.items.allSatisfy({ $0.visibility == "locked" }), nextPage != nil {
            try await fetchNextPage()
        }
    }

    /// Appends paged results. Search keeps the requested order in one section;
    /// other paged sources are grouped by month like the timeline.
    private func append(_ items: [AssetItem]) {
        guard !items.isEmpty else { return }
        if !showsSectionHeaders {
            if sections.isEmpty { sections = [GridSection(id: "results", title: nil, count: 0, assets: [])] }
            sections[0].assets!.append(contentsOf: items)
            sections[0].count = sections[0].assets!.count
        } else {
            for item in items {
                let key = item.date.map { String(ImmichDate.monthKey($0)) } ?? "unknown"
                if sections.last?.id != key {
                    sections.append(GridSection(id: key, title: ImmichDate.monthTitle(key), count: 0, assets: []))
                }
                sections[sections.count - 1].assets!.append(item)
                sections[sections.count - 1].count += 1
            }
        }
        rebuildIndex()
    }

    private func rebuildIndex() {
        var index: [String: (Int, Int)] = [:]
        for (s, section) in sections.enumerated() {
            for (i, asset) in (section.assets ?? []).enumerated() { index[asset.id] = (s, i) }
        }
        self.index = index
    }

    // MARK: Viewer navigation

    func neighbor(of id: String, delta: Int) async -> AssetItem? {
        guard let pos = index[id] else { return nil }
        var s = pos.section
        var i = pos.item + delta
        while sections.indices.contains(s) {
            if sections[s].assets == nil { await loadSection(id: sections[s].id).value }
            let count = sections[s].assets?.count ?? 0
            if i < 0 {
                s -= 1
                guard sections.indices.contains(s) else { return nil }
                if sections[s].assets == nil { await loadSection(id: sections[s].id).value }
                i = (sections[s].assets?.count ?? 0) - 1
            } else if i >= count {
                if isPaged, s == sections.count - 1, nextPage != nil, !pageFailed {
                    do { try await fetchNextPage() }
                    catch {
                        if !error.isCancellation { pageFailed = true; report(error) }
                        return nil
                    }
                    continue
                }
                s += 1
                i = 0
            } else {
                return sections[s].assets?[i]
            }
        }
        return nil
    }

    // MARK: Selection

    func click(_ id: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorID = id
        } else if flags.contains(.shift), let anchor = anchorID, let a = index[anchor], let b = index[id] {
            let (from, to) = (a.section, a.item) < (b.section, b.item) ? (a, b) : (b, a)
            var ids: Set<String> = []
            for s in from.section...to.section {
                guard let assets = sections[s].assets else { continue }
                let start = s == from.section ? from.item : 0
                let end = s == to.section ? to.item : assets.count - 1
                if start <= end { ids.formUnion(assets[start...end].map(\.id)) }
            }
            selection = ids
        } else {
            selection = [id]
            anchorID = id
        }
    }

    func selectAll() {
        selection = Set(sections.flatMap { $0.assets ?? [] }.map(\.id))
    }

    func open(_ id: String) {
        selection = [id]
        anchorID = id
        viewerID = id
    }

    // MARK: Actions

    func setFavorite(_ ids: [String], _ value: Bool) async {
        guard canMutate(ids), let session else { return }
        do {
            try await session.client.setFavorite(ids, value)
            if source == .favorites && !value {
                remove(ids)
            } else {
                update(ids) { $0.isFavorite = value }
            }
            session.invalidateGrids(except: self)
        } catch { report(error) }
    }

    func toggleFavorite(_ ids: [String]) async {
        let items = ids.compactMap(item)
        await setFavorite(ids, !items.allSatisfy(\.isFavorite))
    }

    func moveToLockedFolder(_ ids: [String]) async {
        guard canMutate(ids), let session else { return }
        do {
            try await session.client.setVisibility(ids, "locked")
            session.exploreRemoveFromGrids(Set(ids))
            session.pipeline.evict(ids: ids)
            Task {
                try? await Task.sleep(for: .seconds(2))
                session.pipeline.evict(ids: ids)
            }
            session.invalidateGrids()
            await reload()
        } catch { report(error) }
    }

    func setArchived(_ ids: [String], _ archived: Bool) async {
        guard canMutate(ids), let session else { return }
        do {
            try await session.client.setVisibility(ids, archived ? "archive" : "timeline")
            if source == .archive || source.excludesArchived {
                remove(ids)
            }
            session.invalidateGrids(except: self)
        } catch { report(error) }
    }

    func delete(_ ids: [String], permanently: Bool) async {
        guard canDelete(ids), let session else { return }
        do {
            try await session.client.delete(ids, force: permanently)
            remove(ids)
            session.invalidateGrids(except: self)
            await session.reloadAlbums()
        } catch { report(error) }
    }

    func restore(_ ids: [String]) async {
        guard canDelete(ids), let session else { return }
        do {
            try await session.client.restore(ids)
            remove(ids)
            session.invalidateGrids(except: self)
        } catch { report(error) }
    }

    var lastError: String?

    private func report(_ error: Error) {
        session?.handle(error)
        lastError = error.localizedDescription
    }

    private func update(_ ids: [String], _ change: (inout AssetItem) -> Void) {
        sortedSmartResults = nil
        for id in ids {
            guard let pos = index[id] else { continue }
            change(&sections[pos.section].assets![pos.item])
        }
    }

    private func remove(_ ids: [String]) {
        sortedSmartResults = nil
        let removed = Set(ids)
        // Move the viewer to a neighbour before the current asset disappears.
        if let viewerID, removed.contains(viewerID), let pos = index[viewerID] {
            let remaining = (sections[pos.section].assets ?? []).filter { !removed.contains($0.id) }
            self.viewerID = remaining.isEmpty ? nil : remaining[min(pos.item, remaining.count - 1)].id
        }
        for s in sections.indices {
            guard let assets = sections[s].assets else { continue }
            let kept = assets.filter { !removed.contains($0.id) }
            if kept.count != assets.count {
                sections[s].assets = kept
                sections[s].count = kept.count
            }
        }
        sections.removeAll { $0.count == 0 && $0.assets != nil }
        selection.subtract(removed)
        rebuildIndex()
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

extension ImmichDate {
    /// "2025-04-01" style key for grouping by month.
    static func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d-01", c.year ?? 0, c.month ?? 0)
    }
}
