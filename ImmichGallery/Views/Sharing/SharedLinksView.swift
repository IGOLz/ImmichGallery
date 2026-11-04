import SwiftUI
import AppKit

@MainActor enum SharingClipboard {
    static func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

struct SharedLinksView: View {
    @Environment(LibrarySession.self) private var session
    @State private var editing: SharedLink?
    @State private var sharingLink: SharedLink?
    @State private var deleting: SharedLink?
    @State private var showCreate = false
    @State private var albumID = ""

    var body: some View {
        @Bindable var sharing = session.sharing
        Group {
            if !sharing.linksAvailable {
                ContentUnavailableView("Shared Links Unavailable", systemImage: "link", description: Text("Shared links are disabled or unavailable on this server."))
            } else {
                List {
                    if sharing.links.isEmpty { Text("No public links. Select photos or choose an album to create one.").foregroundStyle(.secondary) }
                    ForEach(sharing.links) { link in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(link.title, systemImage: link.type == "ALBUM" ? "rectangle.stack" : "photo.on.rectangle")
                                Spacer()
                                Button("Copy Link") { Task { await copy(link) } }
                                Button("Share…") { sharingLink = link }
                                Button("Edit…") { editing = link }
                                Button("Delete…", role: .destructive) { deleting = link }
                            }
                            Text(link.expiresAt.flatMap(ImmichDate.parse).map { $0 <= Date() ? "Expired" : "Expires \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Never expires").font(.caption).foregroundStyle(.secondary)
                            if link.type == "INDIVIDUAL" {
                                NavigationLink("Manage \(link.assets.count) Photos") { SharedLinkAssetsView(linkID: link.id) }
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Shared Links")
        .toolbar {
            ToolbarItem {
                Menu("Share Album", systemImage: "plus") {
                    ForEach(session.albums) { album in
                        Button(album.albumName) { albumID = album.id; showCreate = true }
                    }
                }.disabled(!sharing.linksAvailable || session.albums.isEmpty)
            }
            ToolbarItem { Button("Refresh", systemImage: "arrow.clockwise") { Task { await sharing.reload() } } }
        }
        .sheet(item: $sharingLink) { SharedLinkURLSheet(link: $0) }
        .sheet(item: $editing) { SharedLinkEditor(link: $0) }
        .sheet(isPresented: $showCreate) { SharedLinkEditor(albumID: albumID) }
        .confirmationDialog("Delete public link?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Link", role: .destructive) {
                if let link = deleting { Task { await sharing.perform { try await session.client.deleteSharedLink(link.id) } } }
            }
        } message: { Text("Anyone with this link will lose access. The photos remain in your library.") }
        .sharingError()
        .task { await sharing.reload() }
    }

    private func copy(_ link: SharedLink) async {
        do { SharingClipboard.copy(try await session.client.sharingPublicURL(link)) }
        catch { session.sharing.error = error.localizedDescription }
    }
}

struct SharedLinkAssetsView: View {
    @Environment(LibrarySession.self) private var session
    let linkID: String
    @State private var link: SharedLink?
    @State private var selected: Set<String> = []

    var body: some View {
        VStack {
            Text("To add photos, select them in Library and choose Share → Add to Public Link.").foregroundStyle(.secondary).padding()
            List(selection: $selected) {
                ForEach(link?.assets ?? []) { asset in
                    HStack {
                        RemoteThumbnail(assetID: asset.id).frame(width: 48, height: 48)
                        Text(asset.originalFileName)
                    }.tag(asset.id)
                }
            }
        }
        .navigationTitle(link?.title ?? "Shared Photos")
        .toolbar {
            Button("Remove Selected Photos", systemImage: "minus.circle") {
                Task {
                    await session.sharing.perform { try await session.client.changeSharedLinkAssets(linkID, assetIDs: Array(selected), adding: false) }
                    await load()
                }
            }.disabled(selected.isEmpty || session.sharing.busy)
        }
        .sharingError()
        .task { await load() }
    }
    private func load() async {
        do { link = try await session.client.sharedLink(linkID); selected = [] }
        catch { session.sharing.error = error.localizedDescription }
    }
}

private struct SharingErrorModifier: ViewModifier {
    @Environment(LibrarySession.self) private var session
    func body(content: Content) -> some View {
        content.alert("Sharing Failed", isPresented: Binding(get: { session.sharing.error != nil }, set: { if !$0 { session.sharing.error = nil } })) {
            Button("OK") { session.sharing.error = nil }
        } message: { Text(session.sharing.error ?? "") }
    }
}
extension View {
    func sharingError() -> some View { modifier(SharingErrorModifier()) }
}

private struct SharedLinkURLSheet: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let link: SharedLink
    @State private var url: URL?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(link.title).font(.title2.bold())
            if let url {
                Text(url.absoluteString).textSelection(.enabled)
                HStack {
                    Button("Copy Link") { SharingClipboard.copy(url) }
                    ShareLink(item: url)
                }
            } else if let error { Text(error).foregroundStyle(.red) }
            else { ProgressView("Loading Public URL…") }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 440)
        .task {
            do { url = try await session.client.sharingPublicURL(link) }
            catch { self.error = error.localizedDescription }
        }
    }
}
