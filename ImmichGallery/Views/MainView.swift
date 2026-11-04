import SwiftUI

enum SidebarItem: Hashable {
    case library, favorites, videos, people, albums, archive, trash
    case album(String)
    case search
}

struct MainView: View {
    @Environment(LibrarySession.self) private var session
    @State private var selection: SidebarItem? = .library
    @State private var searchText = ""
    @State private var submittedSearch = ""
    @State private var showSearchFilters = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: session.features.smartSearch ? "Search photos" : "Search file names")
        .searchSuggestions { SearchFieldSuggestions(text: searchText) }
        .searchFocused($searchFocused)
        .focusedSceneValue(\.searchActions, SearchActions(
            find: { selection = .search; searchFocused = true },
            filters: { selection = .search; showSearchFilters = true }))
        .onSubmit(of: .search) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            submittedSearch = query
            selection = .search
        }
        .onChange(of: selection) { _, newValue in
            if newValue != .search { searchText = ""; submittedSearch = ""; showSearchFilters = false }
        }
        .onChange(of: searchText) { _, text in
            if text.isEmpty, selection == .search { submittedSearch = "" }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .library {
        case .library:
            AssetGridContainer(source: .library, title: Text("Library"))
        case .favorites:
            AssetGridContainer(source: .favorites, title: Text("Favorites"))
        case .videos:
            AssetGridContainer(source: .videos, title: Text("Videos"))
        case .archive:
            AssetGridContainer(source: .archive, title: Text("Archive"))
        case .trash:
            AssetGridContainer(source: .trash, title: Text("Recently Deleted"))
        case .people:
            PeopleView()
        case .albums:
            AlbumsView()
        case .album(let id):
            AssetGridContainer(source: .album(id), title: Text(verbatim: session.albums.first { $0.id == id }?.albumName ?? ""))
        case .search:
            SearchView(text: submittedSearch, chooseText: { searchText = $0; submittedSearch = $0 }, showFilters: $showSearchFilters)
        }
    }
}

struct SidebarView: View {
    @Environment(LibrarySession.self) private var session
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Photos") {
                Label("Search", systemImage: "magnifyingglass").tag(SidebarItem.search) // Search
                Label("Library", systemImage: "photo.on.rectangle").tag(SidebarItem.library)
                Label("Favorites", systemImage: "heart").tag(SidebarItem.favorites)
                Label("Videos", systemImage: "video").tag(SidebarItem.videos)
            }
            Section("Collections") {
                Label("Albums", systemImage: "rectangle.stack").tag(SidebarItem.albums)
                if session.features.facialRecognition {
                    Label("People", systemImage: "person.crop.square").tag(SidebarItem.people)
                }
            }
            Section("Utilities") {
                Label("Archive", systemImage: "archivebox").tag(SidebarItem.archive)
                if session.features.trash {
                    Label("Recently Deleted", systemImage: "trash").tag(SidebarItem.trash)
                }
            }
            if !session.albums.isEmpty {
                Section("Albums") {
                    ForEach(session.albums) { album in
                        Label {
                            Text(album.albumName)
                        } icon: {
                            Image(systemName: album.shared ? "person.2.crop.square.stack" : "rectangle.stack")
                        }
                        .tag(SidebarItem.album(album.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
