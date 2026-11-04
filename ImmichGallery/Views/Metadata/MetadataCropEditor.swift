import SwiftUI

struct MetadataCropEditor: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let asset: AssetResponse
    @State private var image: CGImage?
    @State private var edits: [MetadataEdit] = []
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var initialCrop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var error: String?
    @State private var loaded = false

    private var width: Int { asset.exifInfo?.metadataDimensions?.width ?? 0 }
    private var height: Int { asset.exifInfo?.metadataDimensions?.height ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crop").font(.title2)
            Text("Drag a rectangle on the unedited preview. Existing rotation and mirror edits are preserved.").font(.caption)
            if let image {
                let ratio = CGFloat(image.width) / CGFloat(image.height)
                GeometryReader { geo in
                    Image(decorative: image, scale: 1).resizable()
                        .overlay {
                            Rectangle().stroke(.white, lineWidth: 2)
                                .background(.white.opacity(0.12))
                                .frame(width: crop.width * geo.size.width, height: crop.height * geo.size.height)
                                .position(x: crop.midX * geo.size.width, y: crop.midY * geo.size.height)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            let startX = min(1, max(0, value.startLocation.x / geo.size.width))
                            let startY = min(1, max(0, value.startLocation.y / geo.size.height))
                            let endX = min(1, max(0, value.location.x / geo.size.width))
                            let endY = min(1, max(0, value.location.y / geo.size.height))
                            crop = CGRect(x: min(startX, endX), y: min(startY, endY), width: abs(startX - endX), height: abs(startY - endY))
                        })
                }
                .aspectRatio(ratio, contentMode: .fit)
                .frame(width: min(640, 420 * ratio), height: min(420, 640 / ratio))
                .background(.black)
            } else if !loaded { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Reset Crop") { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                Spacer()
                if session.metadata.busy { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(!loaded || image == nil || width < 1 || height < 1 || crop.width * Double(width) < 1 || crop.height * Double(height) < 1)
            }
        }
        .disabled(session.metadata.busy)
        .task {
            do {
                edits = try await session.metadata.loadEdits(asset.id, session: session).edits
                image = await session.pipeline.thumbnail(asset.id, size: .preview, edited: false)
                if let p = edits.first(where: { $0.action == "crop" })?.parameters, width > 0, height > 0 {
                    crop = CGRect(x: Double(p.x ?? 0) / Double(width), y: Double(p.y ?? 0) / Double(height),
                                  width: Double(p.width ?? width) / Double(width), height: Double(p.height ?? height) / Double(height))
                }
                initialCrop = crop
                if width == 0 || height == 0 { error = String(localized: "Original dimensions are unavailable for cropping.") }
                if image == nil { error = String(localized: "Couldn't load the unedited preview.") }
            } catch {
                self.error = error.localizedDescription
            }
            loaded = true
        }
    }

    private func save() {
        guard crop != initialCrop else { dismiss(); return }
        var updated = edits.filter { $0.action != "crop" }
        if crop != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let x = max(0, Int(crop.minX * Double(width)))
            let y = max(0, Int(crop.minY * Double(height)))
            let w = min(width - x, max(1, Int(crop.width * Double(width))))
            let h = min(height - y, max(1, Int(crop.height * Double(height))))
            updated.insert(.init(action: "crop", parameters: .init(x: x, y: y, width: w, height: h)), at: 0)
        }
        Task { if await session.metadata.saveEdits(asset.id, edits: updated, session: session) { dismiss() } }
    }
}
