import SwiftUI

struct MetadataMenuItems: View {
    @Environment(LibrarySession.self) private var session
    let ids: [String]
    var canEditImage = false

    var body: some View {
        Button("Adjust Date and Time…") { session.metadata.present(.date, ids: ids) }
        Button("Assign Location…") { session.metadata.present(.location, ids: ids) }
        if canEditImage, ids.count == 1, !session.metadata.unavailableEdits,
           let version = session.version, version.major > 2 || version.minor >= 5 {
            Divider()
            Button("Rotate Left") { rotate(false) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Rotate Right") { rotate(true) }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
            Button("Crop…") { session.metadata.present(.crop, ids: ids) }
        }
    }

    private func rotate(_ clockwise: Bool) {
        guard let id = ids.first else { return }
        Task { await session.metadata.rotate(id, clockwise: clockwise, session: session) }
    }
}

struct MetadataCommands: Commands {
    let app: AppModel
    @FocusedValue(\.gridModel) private var grid

    var body: some Commands {
        CommandGroup(after: .importExport) {
            if let session = app.session {
                let ids = grid?.viewerID.map { [$0] } ?? Array(grid?.selection ?? [])
                MetadataMenuItems(ids: ids, canEditImage: grid?.selectedItems.allSatisfy { !$0.isVideo && $0.livePhotoVideoID == nil } == true)
                    .environment(session)
                    .disabled(ids.isEmpty || session.metadata.busy || grid?.source == .trash)
            }
        }
    }
}

struct MetadataInspectorControls: View {
    @Environment(LibrarySession.self) private var session
    let asset: AssetResponse
    @State private var description = ""
    @State private var ratingsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Add a Description", text: $description, axis: .vertical)
                .lineLimit(2...6)
            if description != (asset.exifInfo?.description ?? "") {
                Button("Save Description") {
                    let value = description
                    Task { _ = await session.metadata.update(.init(ids: [asset.id], description: value), session: session) }
                }
            }
            if ratingsEnabled {
                HStack(spacing: 5) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            Task { _ = await session.metadata.update(.init(ids: [asset.id], rating: rating), session: session) }
                        } label: {
                            Image(systemName: rating <= (asset.exifInfo?.rating ?? 0) ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(rating) stars")
                    }
                    Button("Clear") {
                        Task { _ = await session.metadata.update(.init(ids: [asset.id], clearRating: true), session: session) }
                    }
                }
            }
            Menu("Edit Metadata") {
                MetadataMenuItems(ids: [asset.id], canEditImage: asset.type == .image && asset.livePhotoVideoId == nil)
            }
        }
        .disabled(session.metadata.busy || asset.isTrashed)
        .task(id: asset.id) {
            description = asset.exifInfo?.description ?? ""
            ratingsEnabled = (try? await session.client.metadataPreferences().ratings?.enabled) == true
        }
    }
}

struct MetadataHost: ViewModifier {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel

    func body(content: Content) -> some View {
        @Bindable var metadata = session.metadata
        content
            .sheet(item: $metadata.presentation) { request in
                MetadataSheet(request: request)
            }
            .alert("Metadata", isPresented: Binding(get: { metadata.error != nil }, set: { if !$0 { metadata.error = nil } })) {
                Button("OK") { metadata.error = nil }
            } message: { Text(metadata.error ?? "") }
            .onChange(of: metadata.revision) {
                Task {
                    var month: String?
                    if let id = model.viewerID, let asset = try? await session.client.asset(id) {
                        metadata.viewerSnapshot = AssetItem(asset)
                        month = ImmichDate.parse(asset.localDateTime).map(ImmichDate.monthKey)
                    }
                    await model.reload()
                    if let month, let index = model.sections.firstIndex(where: { $0.id.hasPrefix(String(month.prefix(7))) }) {
                        model.ensureLoaded(index)
                    }
                }
            }
    }
}
