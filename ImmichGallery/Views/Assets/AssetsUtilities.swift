import SwiftUI

struct AssetsSidebarItems: View {
    @Environment(LibrarySession.self) private var session
    @State private var duplicates = false
    var body: some View {
        Group {
            if duplicates { Label("Duplicates", systemImage: "square.on.square").tag(SidebarItem.duplicates) }
            Label("Large Files", systemImage: "externaldrive").tag(SidebarItem.largeFiles)
            Label("Assign Location", systemImage: "mappin.and.ellipse").tag(SidebarItem.geolocation)
        }
        .task {
            let capabilities: AssetsCapabilities? = try? await session.client.get("server/features")
            duplicates = capabilities?.duplicateDetection == true
        }
    }
}

struct AssetsContextMenu: View {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel
    let ids: [String]
    var body: some View {
        Button("Download ZIP…") { AssetsDownloader.start(ids: ids, session: session) }
        if ids.count > 1 {
            Button("Stack Selection") {
                Task {
                    do {
                        _ = try await session.client.assetsCreateStack(ids.sorted())
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
    @State private var location = false
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
                            Button("Download Selection as ZIP…") { AssetsDownloader.start(ids: model.selection.sorted(), session: session) }
                                .disabled(model.selection.isEmpty)
                            if case .album(let id) = model.source {
                                Button("Download Album as ZIP…") { AssetsDownloader.start(album: id, session: session) }
                            }
                            Button("Assign Location…") { location = true }.disabled(model.selection.isEmpty)
                        }
                    } label: { Label("Asset Utilities", systemImage: "ellipsis.circle") }
                    .disabled(busy)
                }
            }
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
            .sheet(isPresented: $location) { AssetsLocationSheet(ids: model.selection.sorted(), model: model) }
    }
}

struct AssetsLocationSheet: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    let model: AssetGridModel
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var saving = false
    @State private var error: String?
    private var coordinates: (Double, Double)? {
        guard let lat = Double(latitude), let lon = Double(longitude), lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign Location").font(.title2)
            Text("Replace the location of \(ids.count) selected items.")
            TextField("Latitude (-90 to 90)", text: $latitude)
            TextField("Longitude (-180 to 180)", text: $longitude)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Location") {
                    guard let (lat, lon) = coordinates else { return }
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            try await session.client.assetsSetLocation(ids, latitude: lat, longitude: lon)
                            session.invalidateGrids()
                            await model.reload()
                            dismiss()
                        } catch { session.handle(error); self.error = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction).disabled(coordinates == nil || saving)
            }
        }.padding(24).frame(width: 400).disabled(saving)
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
