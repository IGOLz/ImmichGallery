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
    @State private var editingSidebar = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var path = NavigationPath() // Crosslink: a person or a place a link names, and pushed pages
    @State private var crosslink = CrosslinkNavigation() // Crosslink: the link this window is still showing
    @State private var linkPath = NavigationPath() // Crosslink: the path as the link last set it
    @State private var pendingPush: PendingPush? // Crosslink: pushed once the page's new stack appears
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool

    init(initialAlbumID: String? = nil, initialSearch: String? = nil) {
        _selection = State(initialValue: initialAlbumID.map(SidebarItem.album) ?? (initialSearch == nil ? .library : .search))
        _searchText = State(initialValue: initialSearch ?? "")
        _submittedSearch = State(initialValue: initialSearch ?? "")
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: Binding(get: { selection }, set: { select($0) }), editing: $editingSidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .onAppear { pushPending() } // Crosslink: this page's stack exists now
                    .navigationDestination(for: CrosslinkDestination.self) { destination in // Crosslink
                        AssetGridContainer(source: destination.source, title: Text(verbatim: destination.title))
                    }
            }
            .id(selection)
            .modifier(AccountPasswordBanner())
            .modifier(GlobalToolbar(session: session, level: .detailStack))
        }
        .modifier(UploadDropModifier(queue: session.upload)) // Upload
        .modifier(GlobalToolbar(session: session, level: .splitView))
        .modifier(AlbumPresentation()) // Albums
        .onChange(of: session.albumActions.navigationAlbumID) { _, id in
            if let id {
                select(.album(id))
                session.albumActions.navigationAlbumID = nil
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: session.features.smartSearch ? "Search photos" : "Search file names")
        .searchSuggestions { SearchFieldSuggestions(text: searchText) }
        .searchFocused($searchFocused)
        .focusedSceneValue(\.sidebarActions, SidebarActions(editing: $editingSidebar))
        .onChange(of: editingSidebar) { _, editing in if editing { columnVisibility = .all } }
        .focusedSceneValue(\.librarySession, session)
        .focusedSceneValue(\.searchActions, SearchActions(
            find: { select(.search); searchFocused = true },
            filters: { select(.search); showSearchFilters = true }))
        .onReceive(NotificationCenter.default.publisher(for: .viewerShowLibrary, object: session)) { _ in select(.library) }
        .onReceive(NotificationCenter.default.publisher(for: .crosslinkShow, object: session)) { note in // Crosslink
            if let item = note.userInfo?["item"] as? Crosslink.Item { showCrosslink(item) }
        }
        // Crosslink: another link came, the user pushed or popped a page, or the window closed (also on signing out
        // or switching accounts): what this window was still doing for a link is stale.
        .onReceive(NotificationCenter.default.publisher(for: .crosslinkArrived)) { _ in dropLink() }
        .onChange(of: path) { _, path in if path != linkPath { dropLink() } }
        .onDisappear { dropLink() }
        .onSubmit(of: .search) {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            submittedSearch = query
            select(.search)
        }
        .onChange(of: selection) { _, newValue in
            if newValue != .search { searchText = ""; submittedSearch = ""; showSearchFilters = false }
        }
        .onChange(of: session.sharing.receivedPartners.map(\.id)) { _, ids in
            if case .partner(let id) = selection, !ids.contains(id) { select(.partners) }
        }
        .onChange(of: searchText) { _, text in
            if text.isEmpty, selection == .search { submittedSearch = "" }
        }
    }

    /// Changes the page, clearing pages pushed on the old one first, so the new page's stack never sees them. Not a
    /// link's doing, so it leaves any link this window was still showing.
    private func select(_ item: SidebarItem?) {
        dropLink()
        path = NavigationPath()
        selection = item
    }

    // MARK: Crosslink

    /// A page a link pushes once its page's new stack exists.
    private struct PendingPush {
        let page: SidebarItem
        let ticket: CrosslinkNavigation.Ticket
        let push: (inout NavigationPath) -> Void
    }

    private func dropLink() {
        crosslink.invalidate()
        pendingPush = nil
    }

    /// A link changes the page.
    private func linkSelect(_ item: SidebarItem) {
        linkPath = NavigationPath()
        path = linkPath
        selection = item
    }

    private func pushPending() {
        guard let pending = pendingPush, pending.page == selection else { return }
        pendingPush = nil
        guard crosslink.isCurrent(pending.ticket) else { return }
        var pushed = NavigationPath()
        pending.push(&pushed)
        linkPath = pushed
        path = pushed
    }

    // Crosslink: shows what a link from another app names, in the page Immich's web app would show it on.
    private func showCrosslink(_ item: Crosslink.Item) {
        pendingPush = nil
        let ticket = crosslink.begin()
        switch item {
        case .page(let page):
            let target: SidebarItem = switch page {
            case .photos: .library
            case .albums: .albums
            case .people: .people
            case .places: .explore(.places)
            case .favorites: .favorites
            case .archive: .archive
            }
            linkSelect(target)
        case .album(let id): linkSelect(.album(id))
        case .person(let id): openPerson(id, ticket: ticket)
        case .place(let place): open(.explore(.places), ticket: ticket) { $0.append(CrosslinkDestination.place(place)) }
        case .asset(let id, let context):
            let alone = { openWindow(id: "widget-photo", value: id) } // as the desktop widget shows a photo
            let reveal = { (source: GridSource) in
                session.crosslinkReveal(id, in: source, ticket: ticket, navigation: crosslink, alone: alone)
            }
            switch context {
            case .album(let album)?:
                linkSelect(.album(album))
                reveal(.album(album))
            case .person(let person)?:
                openPerson(person, ticket: ticket) { reveal(.person(person)) }
            case .favorites?:
                linkSelect(.favorites)
                reveal(.favorites)
            case .archive?:
                linkSelect(.archive)
                reveal(.archive)
            case .search(let place)?:
                let destination = CrosslinkDestination.place(place)
                open(.explore(.places), ticket: ticket) { $0.append(destination) }
                reveal(destination.source)
            case nil:
                linkSelect(.library)
                reveal(.library)
            }
        }
    }

    /// Selects a page, then pushes onto it: now if it is the page shown, or once its new stack appears (a new
    /// selection makes a new stack), if the link is still current then.
    private func open(_ page: SidebarItem, ticket: CrosslinkNavigation.Ticket,
                      pushing push: @escaping (inout NavigationPath) -> Void) {
        let shown = selection == page
        linkSelect(page)
        if shown {
            push(&linkPath)
            path = linkPath
        } else {
            pendingPush = PendingPush(page: page, ticket: ticket, push: push)
        }
    }

    private func openPerson(_ id: String, ticket: CrosslinkNavigation.Ticket, then: @escaping () -> Void = {}) {
        let client = session.client
        let navigation = crosslink
        navigation.run(ticket) {
            await navigation.fetchThenShow(ticket, fetch: { try await client.person(id) }, show: { person in
                open(.people, ticket: ticket) { $0.append(person) }
                then()
            }, failed: { CrosslinkReceiver.cannotShow($0, session: session) })
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
            AlbumDetailView(id: id, onClose: { select(.albums) }) // Albums
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

/// The Import item. macOS 26 attaches it to the split view, so it stays visible on pushed
/// pages too. On macOS 15 that combination with a pushed page's own toolbar loops forever
/// (100% CPU, frozen window), so there it belongs to the detail stack: shown on the main
/// pages, hidden on pushed ones (Back brings it back; File > Import… covers it). Account and
/// notifications live at the bottom of the sidebar instead.
private struct GlobalToolbar: ViewModifier {
    enum Level { case splitView, detailStack }
    let session: LibrarySession
    let level: Level

    func body(content: Content) -> some View {
        if attached {
            content
                .toolbar { UploadToolbar(queue: session.upload) } // Upload
        } else {
            content
        }
    }

    private var attached: Bool {
        if #available(macOS 26, *) { level == .splitView } else { level == .detailStack }
    }
}
