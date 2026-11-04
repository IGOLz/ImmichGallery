import SwiftUI

struct AlbumDetailView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var album: AlbumDetails?
    @State private var error: String?
    @State private var editing = false
    @State private var sharing = false
    @State private var deleting = false
    @State private var leaving = false
    @State private var showActivity = false
    @State private var removed = false

    private var model: AssetGridModel { session.gridModel(for: .album(id)) }

    var body: some View {
        Group {
            if removed {
                ContentUnavailableView("Album Closed", systemImage: "rectangle.stack")
            } else if let album {
                VStack(spacing: 0) {
                    if model.viewerID == nil { header(album) }
                    HStack(spacing: 0) {
                        AssetGridContainer(source: .album(id), title: Text(verbatim: album.albumName))
                        if showActivity && album.shared && album.isActivityEnabled == true {
                            Divider()
                            AlbumActivityPanel(album: album, assetID: model.viewerID)
                                .id(model.viewerID ?? "album")
                                .frame(width: 280)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Menu {
                            if album.isOwner(session.user?.id) {
                                Button("Edit Album…") { editing = true }
                                Button("Manage Sharing…") { sharing = true }
                                Menu("Sort Photos") {
                                    Button("Oldest First") { update(AlbumUpdate(order: "asc")) }
                                    Button("Newest First") { update(AlbumUpdate(order: "desc")) }
                                }
                                if album.isActivityEnabled != nil {
                                    Button(album.isActivityEnabled == true ? "Disable Activity" : "Enable Activity") {
                                        update(AlbumUpdate(isActivityEnabled: album.isActivityEnabled != true))
                                    }
                                }
                                Divider()
                                Button("Delete Album…", role: .destructive) { deleting = true }
                            } else if album.albumUsers?.contains(where: { $0.id == session.user?.id }) == true {
                                Button("View Members…") { sharing = true }
                                Button("Leave Album…", role: .destructive) { leaving = true }
                            }
                            if album.shared && album.isActivityEnabled == true {
                                Toggle("Show Activity", isOn: $showActivity)
                            }
                        } label: { Label("Album Options", systemImage: "ellipsis.circle") }
                    }
                }
            } else if let error {
                ContentUnavailableView { Label("Couldn't Load Album", systemImage: "rectangle.stack.badge.minus") }
                description: { Text(error) } actions: { Button("Try Again") { Task { await load() } } }
            } else { ProgressView() }
        }
        .task(id: id) { await load() }
        .onChange(of: session.albumActions.revision) {
            guard !removed else { return }
            Task { await load(); await model.reload() }
        }
        .sheet(isPresented: $editing) {
            if let album {
                AlbumNameSheet(title: "Edit Album", name: album.albumName, description: album.description ?? "") { name, description in
                    self.album = try await session.client.updateAlbum(id, AlbumUpdate(albumName: name, description: description))
                    session.albumActions.details[id] = self.album
                    await session.reloadAlbums()
                }
            }
        }
        .sheet(isPresented: $sharing, onDismiss: { Task { await load() } }) {
            if let album { AlbumSharingSheet(album: album) }
        }
        .confirmationDialog("Delete Album?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Album", role: .destructive) { closeAlbum(leaving: false) }
        } message: { Text("The album will be deleted for everyone. Its photos and videos stay in the library.") }
        .confirmationDialog("Leave Album?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave Album", role: .destructive) { closeAlbum(leaving: true) }
        } message: { Text("You will lose access to this album until the owner invites you again.") }
        .alert("Album Error", isPresented: Binding(get: { album != nil && error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func header(_ album: AlbumDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(album.albumName).font(.largeTitle.bold()).textSelection(.enabled)
            HStack {
                Text("\(album.assetCount) items")
                if let start = album.startDate.flatMap(ImmichDate.parse) {
                    Text(start, style: .date)
                    if let end = album.endDate.flatMap(ImmichDate.parse), end != start { Text("–"); Text(end, style: .date) }
                }
                if let owner = album.albumOwner { Text("By \(owner.name)") }
            }.font(.callout).foregroundStyle(.secondary)
            if let description = album.description, !description.isEmpty { Text(description).textSelection(.enabled) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }

    private func load() async {
        do {
            let detail = try await session.client.albumDetails(id)
            if model.albumOrder != detail.order ?? "desc" { model.markStale() }
            model.albumOrder = detail.order ?? "desc"
            session.albumActions.details[id] = detail
            album = detail
            error = nil
        } catch { session.handle(error); self.error = error.localizedDescription }
    }

    private func update(_ update: AlbumUpdate) {
        Task {
            do {
                album = try await session.client.updateAlbum(id, update)
                session.albumActions.details[id] = album
                model.albumOrder = album?.order ?? "desc"
                await model.reload()
                await session.reloadAlbums()
            } catch { session.handle(error); self.error = error.localizedDescription }
        }
    }

    private func closeAlbum(leaving: Bool) {
        Task {
            do {
                if leaving { try await session.client.removeAlbumUser(id, userID: "me") }
                else { try await session.client.deleteAlbum(id) }
                removed = true
                session.invalidateGrids()
                await session.reloadAlbums()
                dismiss()
            } catch { session.handle(error); self.error = error.localizedDescription }
        }
    }
}
