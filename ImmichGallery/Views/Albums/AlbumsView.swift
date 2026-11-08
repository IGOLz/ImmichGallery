import SwiftUI

struct AlbumsView: View {
    @Environment(LibrarySession.self) private var session
    // Albums: the same settings and defaults as the albums page of the Immich web app.
    @AppStorage("albums.filter") private var filter = AlbumsFilter.all
    @AppStorage("albums.groupBy") private var groupBy = AlbumsGroupBy.year
    @AppStorage("albums.groupOrder") private var groupOrder = AlbumsSortOrder.descending
    @AppStorage("albums.sortBy") private var sortBy = AlbumsSortBy.mostRecentPhoto
    @AppStorage("albums.sortOrder") private var sortOrder = AlbumsSortOrder.descending

    private var arrangement: AlbumsArrangement {
        AlbumsArrangement(filter: filter, groupBy: groupBy, groupOrder: groupOrder, sortBy: sortBy, sortOrder: sortOrder)
    }

    var body: some View {
        let groups = arrangement.groups(session.albums, userID: session.user?.id)
        Group {
            if groups.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "rectangle.stack",
                                       description: Text("Albums you create or that are shared with you appear here."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)], spacing: 24, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.albums) { album in
                                    NavigationLink(value: album) { AlbumCell(album: album, pipeline: session.pipeline) }.buttonStyle(.plain)
                                        .contextMenu { MacAlbumWindowMenu(albumID: album.id) } // MacIntegration
                                }
                            } header: {
                                if let header = group.header { SectionHeader(title: title(header)).padding(.horizontal, -10) }
                            }
                        }
                    }.padding(20)
                }
                .fastWheelScrolling()
            }
        }
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(id: album.id)
        }
        .toolbar {
            ToolbarItem { viewOptions }
            ToolbarItem { Button { session.albumActions.newAlbum() } label: { Label("New Album", systemImage: "plus") } }
        }
        .task { await session.reloadAlbums() }
    }

    private var viewOptions: some View {
        Menu {
            Section("Show") {
                ForEach(AlbumsFilter.allCases) { option in
                    choice(option.title, selected: filter == option) { filter = option }
                }
            }
            Section("Group By") {
                ForEach(AlbumsGroupBy.allCases) { option in
                    choice(option.title, selected: arrangement.effectiveGroupBy == option) {
                        guard groupBy != option else { return }
                        groupBy = option
                        groupOrder = option.defaultOrder
                    }
                    .disabled(!arrangement.allows(option))
                }
                orderPicker($groupOrder).disabled(arrangement.effectiveGroupBy == .none)
            }
            Section("Sort By") {
                ForEach(AlbumsSortBy.allCases) { option in
                    choice(option.title, selected: sortBy == option) {
                        guard sortBy != option else { return }
                        sortBy = option
                        sortOrder = option.defaultOrder
                    }
                }
                orderPicker($sortOrder)
            }
        } label: {
            Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("View Options")
    }

    private func choice(_ title: LocalizedStringResource, selected: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { selected }, set: { _ in action() })) { Text(title) }
    }

    private func orderPicker(_ order: Binding<AlbumsSortOrder>) -> some View {
        Picker("Order", selection: order) {
            ForEach(AlbumsSortOrder.allCases) { Text($0.title).tag($0) }
        }
    }

    private func title(_ header: AlbumsGroup.Header) -> String {
        switch header {
        case .year(let year): String(year)
        case .unknownYear: String(localized: "Unknown Year")
        case .mine: String(localized: "My Albums")
        case .owner(let name): name
        }
    }
}

private struct AlbumCell: View {
    let album: Album
    let pipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteThumbnail(pipeline: pipeline, assetID: album.albumThumbnailAssetId, size: .preview)
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
