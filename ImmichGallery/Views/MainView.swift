import SwiftUI

enum SidebarItem: Hashable {
    case library, favorites, videos, people, albums, archive, trash
    case album(String)
    case search
    case sharedLinks // Sharing
    case partners // Sharing
    case partner(String) // Sharing
    case duplicates, largeFiles, geolocation // Assets
    case explore(ExplorePage) // Explore
}

struct MainView: View {
    @Environment(LibrarySession.self) private var session
    @State private var selection: SidebarItem? = .library
    @State private var searchText = ""
    @State private var submittedSearch = ""
    @State private var showSearchFilters = false
    @FocusState private var searchFocused: Bool

    init(initialAlbumID: String? = nil, initialSearch: String? = nil) {
        _selection = State(initialValue: initialAlbumID.map(SidebarItem.album) ?? (initialSearch == nil ? .library : .search))
        _searchText = State(initialValue: initialSearch ?? "")
        _submittedSearch = State(initialValue: initialSearch ?? "")
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
            .safeAreaInset(edge: .top, spacing: 0) { AccountPasswordBanner() }
        }
        .modifier(UploadDropModifier(queue: session.upload)) // Upload
        .toolbar { UploadToolbar(queue: session.upload) } // Upload
        .toolbar { ToolbarItemGroup { AccountNotificationBell(session: session.services); AccountMenu() } } // Account
        .modifier(AlbumPresentation()) // Albums
        .onChange(of: session.albumActions.navigationAlbumID) { _, id in
            if let id {
                selection = .album(id)
                session.albumActions.navigationAlbumID = nil
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: session.features.smartSearch ? "Search photos" : "Search file names")
        .searchSuggestions { SearchFieldSuggestions(text: searchText) }
        .searchFocused($searchFocused)
        .focusedSceneValue(\.librarySession, session)
        .focusedSceneValue(\.searchActions, SearchActions(
            find: { selection = .search; searchFocused = true },
            filters: { selection = .search; showSearchFilters = true }))
        .onReceive(NotificationCenter.default.publisher(for: .viewerShowLibrary, object: session)) { _ in selection = .library }
        .onSubmit(of: .search) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            submittedSearch = query
            selection = .search
        }
        .onChange(of: selection) { _, newValue in
            if newValue != .search { searchText = ""; submittedSearch = ""; showSearchFilters = false }
        }
        .onChange(of: session.sharing.receivedPartners.map(\.id)) { _, ids in
            if case .partner(let id) = selection, !ids.contains(id) { selection = .partners }
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
            AlbumDetailView(id: id, onClose: { selection = .albums }) // Albums
        case .sharedLinks: SharedLinksView() // Sharing
        case .partners: PartnersView() // Sharing
        case .partner(let id): AssetGridContainer(source: .partner(id), title: Text(session.sharing.receivedPartners.first { $0.id == id }?.name ?? "Partner Library")) // Sharing
        case .duplicates: AssetsDuplicatesView()
        case .largeFiles: AssetGridContainer(source: .largeFiles, title: Text("Large Files"))
        case .geolocation: AssetGridContainer(source: .geolocation, title: Text("Assign Location"))
        case .explore(let page): ExploreView(page: page) // Explore
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
            ExploreSidebar() // Explore
            Section("Collections") {
                Label("Albums", systemImage: "rectangle.stack").tag(SidebarItem.albums)
                if session.features.facialRecognition {
                    Label("People", systemImage: "person.crop.square").tag(SidebarItem.people)
                }
            }
            SharingSidebar() // Sharing
            Section("Utilities") {
                AssetsSidebarItems()
                Label("Archive", systemImage: "archivebox").tag(SidebarItem.archive)
                if session.features.trash {
                    Label("Recently Deleted", systemImage: "trash").tag(SidebarItem.trash)
                }
            }
            AlbumSidebarSections() // Albums
        }
        .listStyle(.sidebar)
    }
}
