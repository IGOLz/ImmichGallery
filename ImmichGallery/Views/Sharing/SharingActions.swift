import SwiftUI

struct SharingPresentation: Identifiable {
    enum Kind { case create, add, files }
    let id = UUID()
    let kind: Kind
    let assetIDs: [String]
    var albumID: String?
}

struct SharingMenu: View {
    @Environment(LibrarySession.self) private var session
    let assetIDs: [String]
    var albumID: String?
    var body: some View {
        Menu {
            SharingMenuItems(assetIDs: assetIDs, albumID: albumID)
        } label: { Label("Share", systemImage: "square.and.arrow.up") }
        .disabled(assetIDs.isEmpty && albumID == nil)
    }
}

struct SharingMenuItems: View {
    @Environment(LibrarySession.self) private var session
    let assetIDs: [String]
    var albumID: String?
    var body: some View {
        if session.sharing.linksAvailable {
            if let albumID {
                Button("Create Album Public Link…") { session.sharing.presentation = .init(kind: .create, assetIDs: [], albumID: albumID) }
            }
            if !assetIDs.isEmpty {
                Button("Create Public Link…") { session.sharing.presentation = .init(kind: .create, assetIDs: assetIDs) }
            }
            if !assetIDs.isEmpty {
                Button("Add to Public Link…") { session.sharing.presentation = .init(kind: .add, assetIDs: assetIDs) }
            }
        }
        if !assetIDs.isEmpty {
            Button("Share Original Files…") { session.sharing.presentation = .init(kind: .files, assetIDs: assetIDs) }
        }
    }
}

private struct SharingPresentationModifier: ViewModifier {
    @Environment(LibrarySession.self) private var session
    func body(content: Content) -> some View {
        @Bindable var sharing = session.sharing
        content.sheet(item: $sharing.presentation) { presentation in
            switch presentation.kind {
            case .create: SharedLinkEditor(albumID: presentation.albumID, assetIDs: presentation.assetIDs)
            case .add: AddToSharedLinkView(assetIDs: presentation.assetIDs)
            case .files: ShareFilesView(assetIDs: presentation.assetIDs)
            }
        }
    }
}
extension View {
    func sharingPresentation() -> some View { modifier(SharingPresentationModifier()) }
}

private struct AddToSharedLinkView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let assetIDs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to Public Link").font(.title2.bold())
            Text("The selected photos will become accessible to anyone who can open the link.")
            List(session.sharing.links.filter { $0.type == "INDIVIDUAL" }) { link in
                Button(link.title) {
                    Task {
                        await session.sharing.perform { try await session.client.changeSharedLinkAssets(link.id, assetIDs: assetIDs, adding: true) }
                        if session.sharing.error == nil { dismiss() }
                    }
                }.disabled(session.sharing.busy)
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 440, height: 360).sharingError()
            .task { await session.sharing.reload() }
    }
}

private struct ShareFilesView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let assetIDs: [String]
    @State private var urls: [URL] = []
    @State private var completed = 0
    @State private var error: String?
    @State private var folder: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Share Original Files").font(.title2.bold())
            if let error { Text(error).foregroundStyle(.red) }
            else if completed < assetIDs.count {
                ProgressView("Downloading \(completed) of \(assetIDs.count)", value: Double(completed), total: Double(assetIDs.count))
            } else {
                ShareLink(items: urls) { Label("Share \(urls.count) Files…", systemImage: "square.and.arrow.up") }
                Text("Originals include embedded metadata such as location.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 420)
        .task { await download() }
        .onDisappear {
            // Share services may still be copying files after the sheet closes.
            if let folder {
                Task { try? await Task.sleep(for: .seconds(3600)); try? FileManager.default.removeItem(at: folder) }
            }
        }
    }
    private func download() async {
        do {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ImmichShare-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            folder = destination
            for id in assetIDs {
                try Task.checkCancellation()
                let asset = try await session.client.asset(id)
                let (temp, response) = try await session.client.session.download(for: session.client.originalRequest(id))
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw ImmichError.http(400, "Couldn't download an original.") }
                // Separate directories preserve original names and avoid collisions or path traversal.
                let itemFolder = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
                let name = URL(fileURLWithPath: asset.originalFileName).lastPathComponent
                let file = itemFolder.appendingPathComponent(name.isEmpty ? id : name)
                try FileManager.default.moveItem(at: temp, to: file)
                urls.append(file)
                completed += 1
            }
        } catch { if !error.isCancellation { self.error = error.localizedDescription; session.handle(error) } }
    }
}
