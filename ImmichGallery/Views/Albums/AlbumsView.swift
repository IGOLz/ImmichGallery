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
            if groups.isEmpty && !session.albums.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Albums", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No albums match the selected filter.")
                } actions: {
                    Button("Show All Albums") { filter = .all }
                }
            } else if groups.isEmpty {
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
            Picker("Show", selection: $filter) {
                ForEach(AlbumsFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Section("Group By") {
                Picker("Group By", selection: Binding(
                    get: { arrangement.effectiveGroupBy },
                    set: { option in
                        guard groupBy != option else { return }
                        groupBy = option
                        groupOrder = option.defaultOrder
                    }
                )) {
                    ForEach(AlbumsGroupBy.allCases) { option in
                        Text(option.title).tag(option).disabled(!arrangement.allows(option))
                    }
                }
                .pickerStyle(.inline)
                orderPicker("Group Order", $groupOrder).disabled(arrangement.effectiveGroupBy == .none)
            }
            Section("Sort By") {
                Picker("Sort By", selection: Binding(
                    get: { sortBy },
                    set: { option in
                        guard sortBy != option else { return }
                        sortBy = option
                        sortOrder = option.defaultOrder
                    }
                )) {
                    ForEach(AlbumsSortBy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                orderPicker("Album Order", $sortOrder)
            }
        } label: {
            Label("View Options", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("View Options")
    }

    private func orderPicker(_ title: LocalizedStringKey, _ order: Binding<AlbumsSortOrder>) -> some View {
        Picker(title, selection: order) {
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
