import SwiftUI

struct AssetsStackButton: View {
    @Environment(LibrarySession.self) private var session
    let assetID: String
    let model: AssetGridModel
    @State private var stack: AssetsStackSummary?
    @State private var presented = false
    var body: some View {
        Group {
            if let stack {
                Button { presented = true } label: { Label("Browse Stack (\(stack.assetCount))", systemImage: "square.stack.3d.up") }
                    .buttonStyle(.bordered).padding()
                    .sheet(isPresented: $presented) { AssetsStackBrowser(stackID: stack.id, model: model) }
            }
        }.task(id: assetID) {
            stack = nil
            do { stack = try await session.client.asset(assetID).stack }
            catch { session.handle(error) }
        }
    }
}

struct AssetsStackBrowser: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let stackID: String
    let model: AssetGridModel
    @State private var stack: AssetsStack?
    @State private var selected: String?
    @State private var error: String?
    @State private var busy = false
    @State private var unstack = false
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Stack").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let stack, let asset = stack.assets.first(where: { $0.id == selected }) {
                AssetsPreview(asset: asset).frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(stack.assets) { member in
                            Button { selected = member.id } label: {
                                ThumbnailCell(asset: AssetItem(member), isSelected: selected == member.id, size: .thumbnail)
                                    .frame(width: 80, height: 80)
                            }.buttonStyle(.plain).help(member.originalFileName)
                        }
                    }
                }
                HStack {
                    Text(asset.originalFileName).lineLimit(1)
                    Spacer()
                    Button("Set Primary") { perform { _ = try await session.client.assetsSetPrimary(stack: stackID, asset: asset.id) } }
                        .disabled(asset.id == stack.primaryAssetId)
                    Button("Remove from Stack") { perform { try await session.client.assetsRemoveFromStack(stackID, asset: asset.id) } }
                    Button("Unstack…") { unstack = true }
                }.disabled(busy)
            } else if error == nil { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .padding(20).frame(minWidth: 700, idealWidth: 900, minHeight: 550, idealHeight: 700)
        .task { await load() }
        .onDisappear { Task { await model.reload() } }
        .confirmationDialog("Unstack all members?", isPresented: $unstack, titleVisibility: .visible) {
            Button("Unstack") { perform { try await session.client.assetsUnstack(stackID); dismiss() } }
        } message: { Text("All photos remain in your library.") }
    }
    private func load() async {
        do {
            stack = try await session.client.assetsStack(stackID)
            if stack?.assets.contains(where: { $0.id == selected }) != true { selected = stack?.primaryAssetId }
        } catch ImmichError.http(404, _) { dismiss() }
        catch { session.handle(error); self.error = error.localizedDescription }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await action()
                session.invalidateGrids()
                await load()
            } catch { session.handle(error); self.error = error.localizedDescription }
        }
    }
}

struct AssetsPreview: View {
    @Environment(LibrarySession.self) private var session
    let asset: AssetResponse
    @State private var image: CGImage?
    var body: some View {
        Group {
            if asset.type == .video {
                VideoPlayerView(url: session.client.videoURL(asset.id), headers: session.client.credential?.headers ?? [:])
            } else if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else { ProgressView() }
        }.task(id: asset.id) { image = nil; image = await session.pipeline.thumbnail(asset.id, size: .preview) }
    }
}
