import SwiftUI

struct AssetsContextMenu: View {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel
    let ids: [String]
    var body: some View {
        if ids.count > 1, model.canMutate(ids) {
            Button("Stack Selection") {
                Task {
                    do {
                        _ = try await session.client.assetsCreateStack(ids)
                        session.invalidateGrids()
                        await model.reload()
                    } catch { session.handle(error); model.lastError = error.localizedDescription }
                }
            }
        }
    }
}

struct AssetsGridUtilities: ViewModifier {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel
    @State private var trashAction: String?
    @State private var busy = false
    @State private var trashDays: Int?
    @State private var similarPhotos = false
    private var supportsLocation: Bool {
        switch model.source {
        case .library, .favorites, .videos, .archive, .largeFiles, .geolocation, .person, .locked: true
        case .album, .search, .filteredSearch, .partner, .explore, .trash: false
        }
    }
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    Menu {
                        if model.source == .trash {
                            if let trashDays { Text("Items are deleted after \(trashDays) days.") }
                            Button("Restore All…") { trashAction = "restore" }
                            Button("Empty Trash…", role: .destructive) { trashAction = "empty" }
                        } else {
                            if case .album(let id) = model.source {
                                Button("Download Album as ZIP…") { AssetsDownloader.start(album: id, session: session) }
                            }
                            if supportsLocation {
                                Button("Assign Location…") { session.metadata.present(.location, ids: model.selection.sorted()) }.disabled(!model.canMutate(model.selection.sorted()))
                            }
                            if SimilarPhotosMenuButton.isAvailable(model.source) { SimilarPhotosMenuButton(isPresented: $similarPhotos) }
                        }
                    } label: { Label("Asset Utilities", systemImage: "ellipsis.circle") }
                    .disabled(busy)
                }
            }
            .similarPhotosSheet(isPresented: $similarPhotos, model: model)
            .task {
                if model.source == .trash {
                    let config: AssetsServerConfig? = try? await session.client.get("server/config")
                    trashDays = config?.trashDays
                }
            }
            .confirmationDialog(trashAction == "empty" ? "Permanently delete every item in Recently Deleted?" : "Restore every item in Recently Deleted?",
                                isPresented: Binding(get: { trashAction != nil }, set: { if !$0 { trashAction = nil } }), titleVisibility: .visible) {
                let action = trashAction ?? "restore"
                Button(action == "empty" ? "Empty Trash" : "Restore All", role: action == "empty" ? .destructive : nil) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await session.client.send("POST", "trash/\(action)")
                            session.invalidateGrids()
                            await model.reload()
                            await session.reloadAlbums()
                        } catch { session.handle(error); model.lastError = error.localizedDescription }
                    }
                }
            } message: { Text(trashAction == "empty" ? "This cannot be undone." : "This restores all trashed items, including items that are not loaded in this view.") }
    }
}

struct AssetsExportMenu: View {
    @Environment(LibrarySession.self) private var session
    let ids: [String]
    var body: some View {
        Menu("Export") {
            Button("Export Unmodified Original…") { Exporter.exportOriginals(ids, session: session) }
            Button("Download as ZIP…") { AssetsDownloader.start(ids: ids, session: session) }
        }
    }
}

struct AssetsLargeFileBadge: View {
    let asset: AssetItem?
    let source: GridSource
    var body: some View {
        if source == .largeFiles, let bytes = asset?.fileSizeInBytes {
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.caption).foregroundStyle(.white).padding(5)
                .background(.black.opacity(0.65), in: .rect(cornerRadius: 4)).padding(5)
        }
    }
}

/// Assign Location: which items have GPS, as in Immich's geolocation utility. Not needed while the page
/// shows only items without a location.
struct AssetsLocationBadge: View {
    let asset: AssetItem?
    let source: GridSource
    let arrangement: GridArrangement?
    var body: some View {
        if source == .geolocation, arrangement?.hidesLocated != true, let asset {
            Group {
                if !asset.hasLocation { Text("No GPS") }
                else if let city = asset.city, !city.isEmpty { Text(verbatim: city) }
                else { Text("GPS") }
            }
            .font(.caption.weight(.medium)).lineLimit(1)
            .foregroundStyle(asset.hasLocation ? Color.black : Color.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(asset.hasLocation ? Color.green : Color.red, in: .capsule).padding(5)
        }
    }
}
