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
    @State private var lastNonSearchSelection: SidebarItem = .library
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
        .modifier(AlbumPresentation()) // Albums
        .searchable(text: $searchText, placement: .toolbar, prompt: session.features.smartSearch ? "Search photos" : "Search file names")
        .searchFocused($searchFocused)
        .background {
            // ⌘F focuses the toolbar search field, like Photos.
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onSubmit(of: .search) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            submittedSearch = query
            if selection != .search, let selection { lastNonSearchSelection = selection }
            selection = .search
        }
        .onChange(of: selection) { _, newValue in
            if newValue != .search { searchText = "" }
        }
        .onChange(of: searchText) { _, text in
            if text.isEmpty, selection == .search { selection = lastNonSearchSelection }
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
            AlbumDetailView(id: id) // Albums
        case .search:
            AssetGridContainer(source: .search(submittedSearch), title: Text("Search"))
                .navigationSubtitle("“\(submittedSearch)”")
        }
    }
}

struct SidebarView: View {
    @Environment(LibrarySession.self) private var session
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Photos") {
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
            AlbumSidebarSections() // Albums
        }
        .listStyle(.sidebar)
    }
}
