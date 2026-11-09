import SwiftUI

enum ExplorePage: String, CaseIterable, Hashable {
    case map = "Map", places = "Places", memories = "Memories", tags = "Tags", folders = "Folders", locked = "Locked Folder"
    var title: LocalizedStringResource {
        switch self {
        case .map: "Map"
        case .places: "Places"
        case .memories: "Memories"
        case .tags: "Tags"
        case .folders: "Folders"
        case .locked: "Locked Folder"
        }
    }
    var icon: String {
        switch self {
        case .map: "map"
        case .places: "globe.europe.africa"
        case .memories: "sparkles.rectangle.stack"
        case .tags: "tag"
        case .folders: "folder"
        case .locked: "lock"
        }
    }
}

struct ExploreView: View {
    let page: ExplorePage
    var body: some View {
        Group {
            switch page {
            case .map: ExploreMapView()
            case .places: ExplorePlacesView()
            case .memories: ExploreMemoriesView()
            case .tags: ExploreTagsView()
            case .folders: ExploreFoldersView()
            case .locked: ExploreLockedView()
            }
        }.navigationTitle(String(localized: page.title))
    }
}

struct ExplorePlacesView: View {
    @Environment(LibrarySession.self) private var session
    @State private var cities: [AssetResponse] = []
    @State private var error: String?
    // Places: the same grouping and default as the places page of the Immich web app.
    @AppStorage("places.groupBy") private var groupBy = PlacesGroupBy.none
    @AppStorage("places.collapsedGroups") private var collapsedGroups = "{}"
    private var collapsed: CollapsedGroups { CollapsedGroups(stored: collapsedGroups) }
    var body: some View {
        let groups = PlacesArrangement(groupBy: groupBy).groups(cities)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240))], spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    let isCollapsed = collapsed.isCollapsed(group.id, in: groupBy.collapsingKey)
                    Section {
                        if !isCollapsed {
                            ForEach(group.places) { asset in
                                if let city = asset.exifInfo?.city {
                                    NavigationLink {
                                        AssetGridContainer(source: .explore(.city(city)), title: Text(city))
                                    } label: {
                                        VStack(alignment: .leading) {
                                            RemoteThumbnail(pipeline: session.pipeline, assetID: asset.id).aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 10))
                                            Text(city).font(.headline)
                                            // The group header already names the country.
                                            if group.header == nil { Text(asset.exifInfo?.country ?? "").foregroundStyle(.secondary) }
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        if let header = group.header {
                            // Like Immich, a country header collapses and expands its places, so collapsing
                            // all groups turns the page into a list of countries.
                            Button {
                                var groups = collapsed
                                groups.toggle(group.id, in: groupBy.collapsingKey)
                                collapsedGroups = groups.stored
                            } label: {
                                SectionHeader(title: title(header), disclosure: isCollapsed ? .collapsed : .expanded, count: group.places.count)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, -10)
                            .accessibilityHint(isCollapsed ? Text("Shows the places in this country") : Text("Hides the places in this country"))
                        }
                    }
                }
            }.padding(20)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Group By", selection: $groupBy) {
                        ForEach(PlacesGroupBy.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Button("Expand All Groups") {
                        var all = collapsed
                        all.set([], in: groupBy.collapsingKey)
                        collapsedGroups = all.stored
                    }
                    .disabled(groupBy == .none)
                    Button("Collapse All Groups") {
                        var all = collapsed
                        all.set(groups.map(\.id), in: groupBy.collapsingKey)
                        collapsedGroups = all.stored
                    }
                    .disabled(groupBy == .none)
                } label: {
                    Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("View Options")
            }
        }
        .overlay { if let error { ContentUnavailableView("Places Unavailable", systemImage: "globe", description: Text(error)) } }
        .task {
            do { cities = try await session.client.exploreCities().filter { $0.visibility != "locked" } }
            catch { self.error = error.localizedDescription }
        }
    }

    private func title(_ header: PlacesGroup.Header) -> String {
        switch header {
        case .country(let country): country
        case .unknownCountry: String(localized: "Unknown Country")
        }
    }
}

struct ExploreFoldersView: View {
    @Environment(LibrarySession.self) private var session
    @State private var roots: [ExploreFolderNode] = []
    @State private var error: String?
    var body: some View {
        List(roots, children: \.children) { node in
            NavigationLink {
                AssetGridContainer(source: .explore(.folder(node.id)), title: Text(node.name))
            } label: { Label(node.name, systemImage: "folder") }.help(node.id)
        }
        .overlay { if let error { ContentUnavailableView("Folders Unavailable", systemImage: "folder", description: Text(error)) } }
        .task {
            do { roots = ExploreFolderNode.tree(try await session.client.explorePaths()) }
            catch { self.error = error.localizedDescription }
        }
    }
}
