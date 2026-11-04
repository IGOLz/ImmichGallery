import SwiftUI

/// This view never passes locked media to the shared image pipeline, grid cache, exporter or AVPlayer.
struct ExploreLockedView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var client: ImmichClient?
    @State private var status: ExploreAuthStatus?
    @State private var unlocked = false
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var assets: [AssetResponse] = []
    @State private var selected: AssetResponse?
    @State private var error: String?
    @State private var busy = false
    @State private var page = 1
    @State private var hasMore = false
    @State private var generation = UUID()
    var body: some View {
        Group {
            if unlocked, let client {
                if let selected {
                    VStack {
                        ExplorePrivateImage(client: client, id: selected.id, preview: true).id(selected.id)
                        HStack {
                            Button("Back to Grid") { self.selected = nil }
                            Button("Remove from Locked Folder") { restore(selected) }
                        }.padding()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220))]) {
                            ForEach(assets) { asset in
                                Button { selected = asset } label: {
                                    ExplorePrivateImage(client: client, id: asset.id).aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain)
                                .contextMenu { Button("Remove from Locked Folder") { restore(asset) } }
                            }
                        }.padding()
                        if hasMore { Button("Load More") { Task { await load() } }.disabled(busy) }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(status?.pinCode == false ? "Set Up Locked Folder" : "Unlock Locked Folder").font(.title2)
                    SecureField("Six-digit PIN", text: $pin).frame(width: 220)
                    if status?.pinCode == false { SecureField("Confirm PIN", text: $confirmation).frame(width: 220) }
                    Button(status?.pinCode == false ? "Set PIN and Unlock" : "Unlock") { Task { await unlock() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(status == nil || busy || pin.range(of: "^[0-9]{6}$", options: .regularExpression) == nil || (status?.pinCode == false && pin != confirmation))
                    Text("Locks when you leave this view or the app becomes inactive.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { if unlocked { Button("Lock", systemImage: "lock.fill") { lock() } } }
        .task {
            let privateClient = session.client.explorePrivateClient()
            client = privateClient
            do { status = try await privateClient.exploreAuth() }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { lock() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { lock() } }
        .alert("Locked Folder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private func unlock() async {
        guard let client else { return }
        busy = true
        let attempt = generation
        defer { busy = false; pin = ""; confirmation = "" }
        do {
            try await client.exploreUnlock(pin, setup: status?.pinCode == false)
            guard attempt == generation, scenePhase == .active else { try? await client.exploreLock(); return }
            status = try await client.exploreAuth()
            guard status?.isElevated == true else { throw ImmichError.http(403, "The server did not unlock this session.") }
            unlocked = true; page = 1
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func load() async {
        guard let client, unlocked else { return }
        let attempt = generation
        busy = true
        defer { busy = false }
        do {
            let result = try await client.exploreLocked(page: page)
            guard unlocked, attempt == generation else { return }
            assets.append(contentsOf: result.items.filter { $0.visibility == "locked" })
            hasMore = result.nextPage != nil || result.nextCursor != nil
            page += 1
        } catch { self.error = error.localizedDescription; lock() }
    }
    private func lock() {
        generation = UUID()
        unlocked = false; assets = []; selected = nil; pin = ""; confirmation = ""
        session.pipeline.removeAll()
        guard let client else { return }
        Task {
            do { try await client.exploreLock() }
            catch { self.error = "Media was cleared locally, but the server session could not be locked: \(error.localizedDescription)" }
        }
    }
    private func restore(_ asset: AssetResponse) {
        guard let client else { return }
        Task {
            do {
                try await client.setVisibility([asset.id], "timeline")
                assets.removeAll { $0.id == asset.id }; selected = nil
                session.invalidateGrids()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ExplorePrivateImage: View {
    let client: ImmichClient
    let id: String
    var preview = false
    @State private var image: CGImage?
    var body: some View {
        Rectangle().fill(.quaternary).overlay {
            if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: preview ? .fit : .fill) }
        }.clipped()
        .task(id: id) {
            image = nil
            if let data = try? await client.data(for: client.thumbnailRequest(id, size: preview ? .preview : .thumbnail)), !Task.isCancelled {
                image = ImagePipeline.decode(data, maxPixelSize: preview ? 2400 : 400)
            }
        }
        .onDisappear { image = nil }
    }
}
