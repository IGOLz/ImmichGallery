import SwiftUI

enum GridMetrics {
    static let defaultSize = 150.0
    static let steps: [Double] = [56, 72, 96, 120, 150, 190, 240, 320, 420]

    static func zoomIn(_ size: Double) -> Double { steps.first { $0 > size + 1 } ?? steps.last! }
    static func zoomOut(_ size: Double) -> Double { steps.last { $0 < size - 1 } ?? steps.first! }
}

/// Resolves the grid model for a source and hosts the grid, the viewer, toolbar and inspector.
struct AssetGridContainer: View {
    @Environment(LibrarySession.self) private var session
    let source: GridSource
    let title: Text

    var body: some View {
        AssetGridHost(model: session.gridModel(for: source), title: title)
            .id(source)
    }
}

struct AssetGridHost: View {
    @Environment(LibrarySession.self) private var session
    @Bindable var model: AssetGridModel
    let title: Text

    @AppStorage("showInspector") private var showInspector = false
    @AppStorage("gridThumbnailSize") private var thumbnailSize = GridMetrics.defaultSize
    @State private var pendingDelete: [String]?
    @State private var playLive = false

    private var viewerItem: AssetItem? {
        model.viewerID.flatMap { id in model.item(id) ?? (session.metadata.viewerSnapshot?.id == id ? session.metadata.viewerSnapshot : nil) }
    }

    private var inspectedID: String? {
        model.viewerID ?? (model.selection.count == 1 ? model.selection.first : nil)
    }

    var body: some View {
        ZStack {
            AssetGridView(model: model, onDelete: requestDelete)
                .opacity(model.viewerID == nil ? 1 : 0)
                .allowsHitTesting(model.viewerID == nil)
            if let item = viewerItem {
                AssetViewer(model: model, item: item, playLive: $playLive, onDelete: requestDelete)
                    .id("\(item.id)-\(session.metadata.imageRevision)") // Metadata
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.viewerID)
        .modifier(MetadataHost(model: model)) // Metadata
        .navigationTitle(viewerItem?.date.map { Text(ImmichDate.day($0)) } ?? title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sharingPresentation() // Sharing
        .modifier(AssetsGridUtilities(model: model))
        .inspector(isPresented: $showInspector) {
            AssetInspector(assetID: inspectedID)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .task(id: session.macGridRevision) { await model.loadIfNeeded() }
        .onChange(of: session.upload.revision) { Task { await model.reload() } } // Upload
        .focusedSceneValue(\.gridModel, model)
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(model.source == .trash ? "Delete Permanently" : "Delete", role: .destructive) {
                let ids = pendingDelete ?? []
                Task { await model.delete(ids, permanently: model.source == .trash || !session.features.trash) }
            }
        } message: {
            Text(model.source == .trash || !session.features.trash
                 ? "This can't be undone."
                 : "Items are moved to Recently Deleted.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onChange(of: model.viewerID) { playLive = false }
        .modifier(ViewerIntegration(model: model))
    }

    private var subtitle: String {
        if let item = viewerItem { return item.date.map(ImmichDate.time) ?? "" }
        let count = model.totalCount
        guard model.state == .loaded, count > 0 else { return "" }
        if !model.selection.isEmpty { return String(localized: "\(model.selection.count) of \(count) selected") }
        return String(localized: "\(count) items")
    }

    private var deleteTitle: String {
        let n = pendingDelete?.count ?? 0
        return model.source == .trash
            ? String(localized: "Permanently delete \(n) items?")
            : String(localized: "Delete \(n) items?")
    }

    private func requestDelete(_ ids: [String]) {
        guard model.canDelete(ids) else { return }
        pendingDelete = ids
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let ids = model.viewerID.map { [$0] } ?? Array(model.selection)
        let items = ids.compactMap(model.item)

        if model.viewerID != nil {
            ToolbarItem(placement: .navigation) {
                Button { model.viewerID = nil } label: { Label("Back", systemImage: "chevron.backward") }
                    .help("Back to grid")
            }
            if viewerItem?.livePhotoVideoID != nil {
                ToolbarItem {
                    Toggle(isOn: $playLive) { Label("Live", systemImage: "livephoto") }
                        .help("Play Live Photo")
                }
            }
        } else {
            ToolbarItem {
                ControlGroup {
                    Button { thumbnailSize = GridMetrics.zoomOut(thumbnailSize) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                    Button { thumbnailSize = GridMetrics.zoomIn(thumbnailSize) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                }
            }
        }

        ToolbarItem { SharingMenu(assetIDs: ids, allowPublicLinks: model.canMutate(ids), albumID: { if case .album(let id) = model.source { return id }; return nil }()) } // Sharing
        if #available(macOS 26, *) { ToolbarSpacer(.fixed) }

        if model.source == .trash {
            ToolbarItem {
                Button { Task { await model.restore(ids) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canDelete(ids))
                    .help("Restore")
            }
        } else if !model.source.isPartner {
            ToolbarItem {
                let allFavorite = !items.isEmpty && items.allSatisfy(\.isFavorite)
                Button { Task { await model.toggleFavorite(ids) } } label: {
                    Label("Favorite", systemImage: allFavorite ? "heart.fill" : "heart")
                }
                .disabled(!model.canMutate(ids))
                .help(allFavorite ? "Unfavorite" : "Favorite")
            }
        }
        if !model.source.isPartner {
            ToolbarItem {
                Button { requestDelete(ids) } label: { Label("Delete", systemImage: "trash") }
                    .disabled(!model.canDelete(ids))
                    .help("Delete")
            }
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                .help("Show Info (⌘I)")
        }
    }
}

struct AssetGridView: View {
    @Environment(LibrarySession.self) private var session
    @Bindable var model: AssetGridModel
    let onDelete: ([String]) -> Void

    @AppStorage("gridThumbnailSize") private var thumbnailSize = GridMetrics.defaultSize
    @State private var zoomBase: Double?

    var body: some View {
        Group {
            if model.sections.isEmpty {
                switch model.state {
                case .idle, .loading:
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Photos", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await model.reload() } }
                    }
                case .loaded:
                    emptyState
                }
            } else {
                grid
            }
        }
    }

    private var emptyState: some View {
        let (title, symbol): (LocalizedStringKey, String) = switch model.source {
        case .favorites: ("No Favorites", "heart")
        case .videos: ("No Videos", "video")
        case .archive: ("Archive Is Empty", "archivebox")
        case .trash: ("No Recently Deleted Items", "trash")
        case .search, .filteredSearch: ("No Results", "magnifyingglass")
        case .partner: ("No Partner Photos", "person.2")
        case .largeFiles: ("No Large Files", "externaldrive")
        case .geolocation: ("No Photos to Locate", "mappin.and.ellipse")
        case .explore: ("No Photos to Explore", "globe")
        default: ("No Photos", "photo.on.rectangle")
        }
        return ContentUnavailableView(title, systemImage: symbol)
    }

    private var thumbnailRequestSize: ImmichClient.ThumbnailSize {
        thumbnailSize * 2 > 320 ? .preview : .thumbnail
    }

    private var grid: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.8), spacing: 2)],
                spacing: 2,
                pinnedViews: model.showsSectionHeaders ? [.sectionHeaders] : []
            ) {
                ForEach(Array(model.sections.enumerated()), id: \.element.id) { s, section in
                    Section {
                        // IDs must be unique across sections: they all live in one lazy container.
                        ForEach((0..<section.count).map { CellKey(section: section.id, index: $0) }, id: \.self) { key in
                            cell(s, key.index)
                        }
                    } header: {
                        if model.showsSectionHeaders, let title = section.title {
                            SectionHeader(title: title)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear { scrollToViewerTarget(proxy) }
        .onChange(of: model.viewerScrollTarget) { scrollToViewerTarget(proxy) }
        }
        .macOriginalDragContainer(model: model, client: session.client)
        .fastWheelScrolling()
        .background {
            // Clicking empty space clears the selection, like Photos.
            Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = [] }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = zoomBase ?? thumbnailSize
                    zoomBase = base
                    thumbnailSize = min(GridMetrics.steps.last!, max(GridMetrics.steps.first!, base * value.magnification))
                }
                .onEnded { _ in zoomBase = nil }
        )
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(action: handleKey)
    }

    private func scrollToViewerTarget(_ proxy: ScrollViewProxy) {
        guard let id = model.viewerScrollTarget else { return }
        for section in model.sections {
            if let index = section.assets?.firstIndex(where: { $0.id == id }) {
                proxy.scrollTo(CellKey(section: section.id, index: index), anchor: .center)
                model.viewerScrollTarget = nil
                return
            }
        }
    }

    private func cell(_ s: Int, _ i: Int) -> some View {
        let asset = model.asset(s, i)
        let thumbnail = ThumbnailCell(
            asset: asset,
            isSelected: asset.map { model.selection.contains($0.id) } ?? false,
            size: thumbnailRequestSize
        )
        return Group {
            if let asset {
                let albumIDs = AlbumAssetTransfer(ids: model.selection.contains(asset.id) ? Array(model.selection) : [asset.id])
                if #available(macOS 26, *) {
                    thumbnail.draggable(albumIDs)
                } else {
                    thumbnail.draggable(LegacyAssetDrag(album: albumIDs, original: OriginalTransfer(id: asset.id, isVideo: asset.isVideo, client: session.client)))
                }
            } else {
                thumbnail
            }
        }
        .overlay(alignment: .topLeading) { AssetsLargeFileBadge(asset: asset, source: model.source) }
        .macOriginalContainerItem(asset.map { OriginalTransfer(id: $0.id, isVideo: $0.isVideo, client: session.client) })
        .onAppear { model.cellAppeared(section: s, item: i) }
        .onTapGesture(count: 2) { if let asset { model.open(asset.id) } }
        .simultaneousGesture(TapGesture().onEnded { if let asset { model.click(asset.id) } })
        .contextMenu {
            if let asset { contextMenu(for: asset) }
        }
    }

    @ViewBuilder
    private func contextMenu(for asset: AssetItem) -> some View {
        let ids = model.selection.contains(asset.id) ? Array(model.selection) : [asset.id]
        Button("Open") { model.open(asset.id) }
        ViewerContextMenu(model: model, asset: asset)
        Divider()
        if !model.canMutate(ids), model.source != .trash {
            SharingMenuItems(assetIDs: ids, allowPublicLinks: false)
            AssetsExportMenu(ids: ids)
        } else if model.source == .trash {
            Button("Restore") { Task { await model.restore(ids) } }.disabled(!model.canDelete(ids))
            Button("Delete Permanently…", role: .destructive) { onDelete(ids) }.disabled(!model.canDelete(ids))
        } else {
            AlbumSelectionMenu(session: session, model: model, ids: ids) // Albums
            Button(asset.isFavorite ? "Unfavorite" : "Favorite") { Task { await model.setFavorite(ids, !asset.isFavorite) } }
            SharingMenu(assetIDs: ids) // Sharing
            AssetsContextMenu(model: model, ids: [asset.id] + ids.filter { $0 != asset.id })
            MetadataMenuItems(ids: ids, canEditImage: !asset.isVideo && asset.livePhotoVideoID == nil).disabled(session.metadata.busy) // Metadata
            ExploreAssetActions(ids: ids, model: model) // Explore
            AssetsExportMenu(ids: ids)
            Divider()
            if model.source == .archive {
                Button("Unarchive") { Task { await model.setArchived(ids, false) } }
            } else {
                Button(String(localized: "Archive Selected Photos")) { Task { await model.setArchived(ids, true) } }
            }
            Button("Delete…", role: .destructive) { onDelete(ids) }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let ids = Array(model.selection)
        switch press.key {
        case .space:
            guard !ids.isEmpty else { return .ignored }
            MacQuickLook.shared.toggle(model.macOrderedSelection, session: session) { model.lastError = $0 }
        case .return:
            guard let first = model.selectedItems.first else { return .ignored }
            model.open(first.id)
        case .delete, .deleteForward:
            guard press.modifiers.contains(.command), !ids.isEmpty else { return .ignored }
            onDelete(ids)
        case .leftArrow, .rightArrow:
            guard let current = model.selection.first, model.selection.count == 1 else { return .ignored }
            Task {
                if let next = await model.neighbor(of: current, delta: press.key == .leftArrow ? -1 : 1) {
                    model.selection = [next.id]
                }
            }
        case .escape:
            model.selection = []
        default:
            if press.characters == "." && !ids.isEmpty {
                Task { await model.toggleFavorite(ids) }
            } else {
                return .ignored
            }
        }
        return .handled
    }
}

private struct CellKey: Hashable {
    let section: String
    let index: Int
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .adaptiveGlass(in: .capsule)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

struct ThumbnailCell: View {
    @Environment(LibrarySession.self) private var session
    let asset: AssetItem?
    let isSelected: Bool
    let size: ImmichClient.ThumbnailSize

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if let hash = asset?.thumbhash, let placeholder = ThumbHash.image(base64: hash) {
                    Image(decorative: placeholder, scale: 1).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: asset?.isVideo == true ? "video.slash" : "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) { badges }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                    Color.accentColor.opacity(0.12)
                }
            }
            .contentShape(Rectangle())
            .task(id: TaskKey(id: asset?.id, size: size, revision: session.metadata.imageRevision)) { await load() }
    }

    private struct TaskKey: Equatable { let id: String?; let size: ImmichClient.ThumbnailSize; let revision: Int }

    private func load() async {
        failed = false
        guard let id = asset?.id else { image = nil; return }
        let pipeline = session.pipeline
        if let cached = pipeline.cachedThumbnail(id, size: size) { image = cached; return }
        image = pipeline.cachedThumbnail(id, size: .thumbnail) ?? pipeline.cachedThumbnail(id, size: .preview)
        if let loaded = await pipeline.thumbnail(id, size: size) { image = loaded }
        else if !Task.isCancelled && image == nil { failed = true }
    }

    @ViewBuilder
    private var badges: some View {
        if let asset, asset.isFavorite || asset.isVideo || asset.livePhotoVideoID != nil || asset.stackCount != nil {
            HStack(spacing: 4) {
                if asset.isFavorite { Image(systemName: "heart.fill") }
                Spacer(minLength: 0)
                if let count = asset.stackCount {
                    Label("\(count)", systemImage: "square.stack.3d.up.fill").labelStyle(.titleAndIcon)
                }
                if asset.livePhotoVideoID != nil { Image(systemName: "livephoto") }
                if asset.isVideo {
                    Text(asset.durationMS.map(Duration.formatMilliseconds) ?? "")
                        .monospacedDigit()
                    Image(systemName: "video.fill")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
