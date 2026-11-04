import SwiftUI

/// Square, cropped thumbnail for an asset id (album covers etc.).
struct RemoteThumbnail: View {
    let pipeline: ImagePipeline
    let assetID: String?
    var size: ImmichClient.ThumbnailSize = .thumbnail
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if assetID == nil {
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: assetID) {
                image = nil
                guard let assetID else { return }
                image = pipeline.cachedThumbnail(assetID, size: size)
                if image == nil {
                    let loaded = await pipeline.thumbnail(assetID, size: size)
                    guard !Task.isCancelled else { return }
                    image = loaded
                }
            }
    }
}
