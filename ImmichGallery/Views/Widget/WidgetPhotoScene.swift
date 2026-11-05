import SwiftUI

/// Opens the photo clicked on the desktop widget (photos from a memory open the memory instead).
struct WidgetPhotoScene: Scene {
    let app: AppModel
    var body: some Scene {
        WindowGroup("Photo", id: "widget-photo", for: String.self) { $id in
            if let services = app.services, let id {
                WidgetPhotoWindow(services: services, id: id).id(ObjectIdentifier(services))
            } else {
                ContentUnavailableView("Sign In to View This Photo", systemImage: "photo",
                                       description: Text("Sign in from the main library window to continue."))
            }
        }
        .defaultSize(width: 1100, height: 760)
    }
}

private struct WidgetPhotoWindow: View {
    let services: AccountServices
    let id: String
    @State private var image: CGImage?
    @State private var asset: AssetResponse?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if failed {
                ContentUnavailableView("Photo Unavailable", systemImage: "photo",
                                       description: Text("It may have been deleted, or it belongs to another account."))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle(asset.flatMap { ImmichDate.parse($0.localDateTime) }.map { Text(ImmichDate.day($0)) } ?? Text("Photo"))
        .navigationSubtitle(asset?.originalFileName ?? "")
        .task(id: id) {
            do {
                asset = try await services.client.asset(id)
            } catch {
                services.handle(error)
                failed = true
                return
            }
            if let preview = await services.pipeline.thumbnail(id, size: .preview) { image = preview }
            if let full = await services.pipeline.thumbnail(id, size: .fullsize) { image = full }
            if image == nil { failed = true }
        }
    }
}
