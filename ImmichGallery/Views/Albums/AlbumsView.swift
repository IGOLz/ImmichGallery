import SwiftUI

struct AlbumsView: View {
    @Environment(LibrarySession.self) private var session

    var body: some View {
        Group {
            if session.albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "rectangle.stack",
                                       description: Text("Albums you create or that are shared with you appear here."))
            } else {
                ScrollView {
                    ForEach([false, true], id: \.self) { shared in
                        let albums = session.albums.filter { $0.shared == shared }
                        if !albums.isEmpty {
                            Text(shared ? "Shared Albums" : "My Albums")
                                .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)], spacing: 24) {
                                ForEach(albums) { album in
                                    NavigationLink(value: album) { AlbumCell(album: album) }.buttonStyle(.plain)
                                        .contextMenu { MacAlbumWindowMenu(albumID: album.id) } // MacIntegration
                                }
                            }.padding(20)
                        }
                    }
                }
                .fastWheelScrolling()
            }
        }
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(id: album.id)
        }
        .toolbar {
            ToolbarItem { Button { session.albumActions.newAlbum() } label: { Label("New Album", systemImage: "plus") } }
        }
        .task { await session.reloadAlbums() }
    }
}

private struct AlbumCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteThumbnail(assetID: album.albumThumbnailAssetId, size: .preview)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
            Text(album.albumName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                if album.shared { Image(systemName: "person.2.fill") }
                Text("\(album.assetCount) items")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Square, cropped thumbnail for an asset id (album covers etc.).
struct RemoteThumbnail: View {
    @Environment(LibrarySession.self) private var session
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
                guard let assetID else { return }
                image = session.pipeline.cachedThumbnail(assetID, size: size)
                if image == nil { image = await session.pipeline.thumbnail(assetID, size: size) }
            }
    }
}
