import SwiftUI

enum ExplorePage: String, CaseIterable, Hashable {
    case map = "Map", places = "Places", memories = "Memories", tags = "Tags", folders = "Folders", locked = "Locked Folder"
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

struct ExploreSidebar: View {
    @Environment(LibrarySession.self) private var session
    private var preferences: ExplorePreferences? { session.services.explorePreferences }
    private var lockedAvailable: Bool { session.services.lockedAvailable }
    var body: some View {
        Section("Explore") {
            ForEach(ExplorePage.allCases, id: \.self) { page in
                if enabled(page) { Label(page.rawValue, systemImage: page.icon).tag(SidebarItem.explore(page)) }
            }
        }
    }
    private func enabled(_ page: ExplorePage) -> Bool {
        switch page {
        case .map: session.features.map
        case .memories: preferences?.memories?.enabled == true
        case .tags: preferences?.tags?.enabled == true
        case .folders: preferences?.folders?.enabled == true
        case .locked: lockedAvailable
        default: true
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
        }.navigationTitle(page.rawValue)
    }
}

struct ExplorePlacesView: View {
    @Environment(LibrarySession.self) private var session
    @State private var cities: [AssetResponse] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240))], spacing: 20) {
                ForEach(cities) { asset in
                    if let city = asset.exifInfo?.city {
                        NavigationLink {
                            AssetGridContainer(source: .explore(.city(city)), title: Text(city))
                        } label: {
                            VStack(alignment: .leading) {
                                RemoteThumbnail(assetID: asset.id).aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 10))
                                Text(city).font(.headline)
                                Text(asset.exifInfo?.country ?? "").foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }
        .overlay { if let error { ContentUnavailableView("Places Unavailable", systemImage: "globe", description: Text(error)) } }
        .task {
            do { cities = try await session.client.exploreCities().filter { $0.visibility != "locked" } }
            catch { self.error = error.localizedDescription }
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
