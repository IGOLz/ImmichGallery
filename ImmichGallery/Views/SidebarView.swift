import SwiftUI

struct SidebarView: View {
    @Environment(LibrarySession.self) private var session
    @Binding var selection: SidebarItem?
    @AppStorage("sidebarLayout") private var storedLayout = ""
    @AppStorage("albums.filter") private var albumsFilter = AlbumsFilter.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Editing happens in the sidebar itself, like Music's Edit and the iPadOS sidebar: hidden sections
    /// and items appear with checkboxes until Done.
    @Binding var editing: Bool
    @State private var frames: [SidebarDropTarget: CGRect] = [:]
    @State private var dragging: SidebarLink?
    @State private var dragCancelled = false
    @State private var dragPreview = SidebarDragPreviewState()
    @State private var dragLayout: SidebarLayout?
    @State private var insertion: SidebarDropPosition?
    @State private var dragOffset = CGSize.zero
    @State private var dragSourceFrame = CGRect.zero
    @State private var settling = false
    @State private var displayedLayout = UserDefaults.standard.string(forKey: "sidebarLayout") ?? ""
    @State private var viewport = CGRect.zero
    @State private var renaming: String?
    @State private var removing: SidebarSection?
    @State private var confirmingReset = false
    @GestureState private var gestureActive = false
    @FocusState private var sidebarFocused: Bool

    private var focusedSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { selection = $0; sidebarFocused = true })
    }

    private var layout: SidebarLayout { SidebarLayout(stored: displayedLayout) }

    var body: some View {
        let layout = self.layout
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(layout.sections.filter { editing || !$0.hidden }) { section in
                            sectionView(section, layout: layout)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .coordinateSpace(name: "sidebarDrag")
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = CGRect(origin: .zero, size: $0) }
                .overlay {
                    ZStack(alignment: .topLeading) {
                        if let dragging {
                            SidebarFloatingPreview(selected: !editing && selection == dragging.presentation.destination, state: dragPreview) {
                                SidebarNavigationLabel(link: dragging)
                            }
                        }
                        if let insertion, let frame = insertion.indicatorFrame(in: frames) {
                            SidebarInsertionIndicator()
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
                .focusable().focusEffectDisabled().focused($sidebarFocused)
                .onKeyPress(.escape) {
                    if dragging == nil, editing, renaming == nil {
                        editing = false
                        return .handled
                    }
                    guard dragging != nil, !settling else { return .ignored }
                    dragging = nil
                    insertion = nil
                    dragCancelled = true
                    return .handled
                }
                .onChange(of: gestureActive) { _, active in if !active && !settling { clearDrag() } }
                .onKeyPress(.upArrow) { navigate(by: -1, scroll: proxy) }
                .onKeyPress(.downArrow) { navigate(by: 1, scroll: proxy) }
                Divider()
                AccountSidebarFooter(services: session.services) { // Account
                    SidebarFooterControls(editing: $editing, hidden: hiddenItems(in: layout),
                                          newSection: { addSection(scroll: proxy) }, reset: { confirmingReset = true })
                }
            }
        }
        .onChange(of: storedLayout, initial: true) { _, value in
            guard displayedLayout != value else { return }
            withAnimation(reorderAnimation) { displayedLayout = value }
        }
        .onChange(of: editing) { _, value in if !value { renaming = nil } }
        .confirmationDialog("Delete this custom section?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Delete Section", role: .destructive) {
                if let section = removing { update { $0.removeSection(id: section.id) } }
                removing = nil
            }
        } message: {
            Text("Items return to their default sections. Your photos and albums are not deleted.")
        }
        .confirmationDialog("Reset the sidebar?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Sidebar", role: .destructive) { storedLayout = "" }
        } message: {
            Text("This restores the default sections and item order, shows hidden items, and removes custom sections. Your photos and albums are not affected.")
        }
    }

    private func sectionView(_ section: SidebarSection, layout: SidebarLayout) -> some View {
        let links = shownLinks(in: section.id, layout: layout)
        return LazyVStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(section: section, editing: editing, renaming: $renaming,
                                 setHidden: { hidden in update { $0.setSectionHidden(hidden, id: section.id) } },
                                 setCollapsed: { collapsed in update { $0.setSectionCollapsed(collapsed, id: section.id) } },
                                 rename: { name in update { $0.renameSection(id: section.id, to: name) } }) {
                headerMenu(section, layout: layout)
            }
            .modifier(SidebarDropRegion(target: SidebarDropTarget(sectionID: section.id), frames: $frames))
            // Editing exposes every item without changing the saved collapsed state.
            if editing || !section.isCollapsed {
                if editing && section.listsAlbums {
                    VStack(alignment: .leading, spacing: 4) {
                        albumLimitPicker(in: section.id, layout: layout)
                        albumSortPicker(in: section.id, layout: layout)
                    }
                    .pickerStyle(.menu).controlSize(.small)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                }
                ForEach(links, id: \.self) { link in
                    Group {
                        if editing {
                            SidebarEditRow(isOn: Binding(get: { !layout.isHidden(link) }, set: { visible in update { $0.setHidden(!visible, link: link) } })) {
                                SidebarNavigationLabel(link: link)
                            }
                        } else {
                            SidebarSelectionRow(item: link.presentation.destination, selection: focusedSelection) {
                                SidebarNavigationRow(link: link, sectionID: section.id, layout: $storedLayout, edit: { editing = true })
                            }
                        }
                    }
                    .opacity(settling && dragging == link ? 0 : 1)
                    .modifier(SidebarDropRegion(target: SidebarDropTarget(sectionID: section.id, link: link), frames: $frames))
                    .highPriorityGesture(dragGesture(link: link, sectionID: section.id))
                    // Drag is the main way to reorder; these keep it possible without a pointer.
                    .accessibilityAction(named: Text("Move Up")) { shift(link, by: -1, in: links, sectionID: section.id) }
                    .accessibilityAction(named: Text("Move Down")) { shift(link, by: 1, in: links, sectionID: section.id) }
                    .id(link.presentation.destination)
                }
                if section.id == SidebarGroup.sharing.rawValue, session.sharing.partnersAvailable {
                    ForEach(session.sharing.receivedPartners.filter { editing || !layout.isDynamicItemHidden(session.sidebarItemKey("partner:" + $0.id)) }) { partner in
                        let key = session.sidebarItemKey("partner:" + partner.id)
                        if editing {
                            SidebarEditRow(isOn: dynamicVisibility(key, layout: layout)) { Label(partner.name, systemImage: "person.2") }
                        } else {
                            SidebarSelectionRow(item: .partner(partner.id), selection: focusedSelection) {
                                Label(partner.name, systemImage: "person.2")
                            }
                            .contextMenu {
                                Button("Hide from Sidebar") { update { $0.setDynamicItemHidden(true, key: key) } }
                            }
                            .id(SidebarItem.partner(partner.id))
                        }
                    }
                }
                if section.listsAlbums {
                    if editing {
                        let albums = session.albums.filter { $0.shared == (section.id == SidebarGroup.sharedAlbums.rawValue) }
                        ForEach(AlbumsArrangement.sidebar(albums, sortBy: layout.albumSortBy(in: section.id), limit: nil)) { album in
                            SidebarEditRow(isOn: dynamicVisibility(session.sidebarItemKey("album:" + album.id), layout: layout)) {
                                Label(album.albumName, systemImage: album.shared ? "person.2.crop.square.stack" : "rectangle.stack")
                            }
                        }
                    } else {
                        AlbumSidebarRows(shared: section.id == SidebarGroup.sharedAlbums.rawValue, storedLayout: $storedLayout, selection: focusedSelection)
                        if session.sidebarAlbumsTruncated(in: section.id, layout: layout) {
                            // Like Finder's All Tags… row: a shortened list says where the rest are.
                            Button {
                                albumsFilter = section.id == SidebarGroup.sharedAlbums.rawValue ? .shared : .owned
                                focusedSelection.wrappedValue = .albums
                            } label: {
                                SidebarRowContent(selected: false, active: false) {
                                    Label("Show All", systemImage: "ellipsis")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .id(section.id)
    }

    @ViewBuilder
    private func headerMenu(_ section: SidebarSection, layout: SidebarLayout) -> some View {
        Button(section.isCollapsed ? "Expand" : "Collapse") { update { $0.setSectionCollapsed(!section.isCollapsed, id: section.id) } }
        if section.listsAlbums {
            Divider()
            albumLimitPicker(in: section.id, layout: layout)
            albumSortPicker(in: section.id, layout: layout)
        }
        Divider()
        if section.isCustom {
            Button("Rename Section") { editing = true; renaming = section.id }
            Button("Delete Section…") { removing = section }
        }
        if !section.hidden {
            Button("Hide Section") { update { $0.setSectionHidden(true, id: section.id) } }
        }
        if !editing {
            Button("Edit Sidebar") { editing = true }
        }
    }

    private func shownLinks(in sectionID: String, layout: SidebarLayout) -> [SidebarLink] {
        layout.links(in: sectionID).filter { session.sidebarLinkAvailable($0) && (editing || !layout.isHidden($0)) }
    }

    private func dynamicVisibility(_ key: String, layout: SidebarLayout) -> Binding<Bool> {
        Binding(get: { !layout.isDynamicItemHidden(key) }, set: { visible in update { $0.setDynamicItemHidden(!visible, key: key) } })
    }

    /// Everything hidden on this server, for the footer's Show in Sidebar menu.
    private func hiddenItems(in layout: SidebarLayout) -> [SidebarHiddenItem] {
        func item(_ id: String, _ title: Text, _ icon: String?, show: @escaping (inout SidebarLayout) -> Void) -> SidebarHiddenItem {
            SidebarHiddenItem(id: id, title: title, icon: icon) { update(show) }
        }
        var items = layout.sections.filter(\.hidden).map { section in
            item("section:" + section.id, section.label, nil) { $0.setSectionHidden(false, id: section.id) }
        }
        items += SidebarLink.allCases.filter { layout.isHidden($0) && session.sidebarLinkAvailable($0) }.map { link in
            item("link:" + link.rawValue, Text(link.presentation.title), link.presentation.icon) { $0.setHidden(false, link: link) }
        }
        if session.sharing.partnersAvailable {
            items += session.sharing.receivedPartners.compactMap { partner in
                let key = session.sidebarItemKey("partner:" + partner.id)
                guard layout.isDynamicItemHidden(key) else { return nil }
                return item(key, Text(verbatim: partner.name), "person.2") { $0.setDynamicItemHidden(false, key: key) }
            }
        }
        items += AlbumsArrangement.sidebar(session.albums, sortBy: .title, limit: nil).compactMap { album in
            let key = session.sidebarItemKey("album:" + album.id)
            guard layout.isDynamicItemHidden(key) else { return nil }
            return item(key, Text(verbatim: album.albumName), album.shared ? "person.2.crop.square.stack" : "rectangle.stack") {
                $0.setDynamicItemHidden(false, key: key)
            }
        }
        return items
    }

    private func addSection(scroll: ScrollViewProxy) {
        var updated = layout
        guard let id = updated.addSection(named: String(localized: "New Section")) else { return }
        storedLayout = updated.stored
        editing = true
        renaming = id
        DispatchQueue.main.async { withAnimation(reorderAnimation) { scroll.scrollTo(id, anchor: .bottom) } }
    }

    private func shift(_ link: SidebarLink, by offset: Int, in links: [SidebarLink], sectionID: String) {
        guard let index = links.firstIndex(of: link), links.indices.contains(index + offset) else { return }
        var updated = layout
        guard updated.move(link, to: sectionID, relativeTo: links[index + offset], after: offset > 0) else { return }
        storedLayout = updated.stored
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88)
    }

    private func clearDrag() {
        dragging = nil
        insertion = nil
        dragLayout = nil
        dragCancelled = false
        settling = false
    }

    private func dragGesture(link: SidebarLink, sectionID: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("sidebarDrag"))
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !dragCancelled && !settling else { return }
                if dragging == nil {
                    dragging = link
                    dragLayout = layout
                    sidebarFocused = true
                    let frame = frames[SidebarDropTarget(sectionID: sectionID, link: link)] ?? .zero
                    dragSourceFrame = frame
                    dragOffset = CGSize(width: value.startLocation.x - frame.minX, height: value.startLocation.y - frame.minY)
                }
                dragPreview.frame = CGRect(origin: CGPoint(x: value.location.x - dragOffset.width, y: value.location.y - dragOffset.height), size: dragSourceFrame.size)
                let next = resolvedMove(at: value.location, source: link, current: dragLayout ?? layout)?.position
                if insertion != next { insertion = next }
            }
            .onEnded { value in
                guard !settling else { return }
                guard dragging == link, let move = resolvedMove(at: value.location, source: link, current: layout),
                      let destination = move.position.landingFrame(for: frames.first(where: { $0.key.link == link })?.value ?? dragSourceFrame, in: frames) else {
                    clearDrag()
                    return
                }
                settling = true
                insertion = nil
                let saved = move.layout.stored
                withAnimation(reorderAnimation, completionCriteria: .logicallyComplete) {
                    displayedLayout = saved
                    dragPreview.frame = destination
                } completion: {
                    clearDrag()
                }
                storedLayout = saved
            }
    }

    private func resolvedMove(at point: CGPoint, source: SidebarLink, current: SidebarLayout) -> (position: SidebarDropPosition, layout: SidebarLayout)? {
        guard session.sidebarLinkAvailable(source), editing || !current.isHidden(source),
              let position = SidebarDropPosition.resolve(at: point, in: viewport, targets: frames) else { return nil }
        let target = position.target.link ?? shownLinks(in: position.target.sectionID, layout: current).first
        var updated = current
        guard updated.move(source, to: position.target.sectionID, relativeTo: target, after: position.target.link != nil && position.edge == .after) else { return nil }
        return (position, updated)
    }

    private func navigate(by offset: Int, scroll: ScrollViewProxy) -> KeyPress.Result {
        guard !editing else { return .ignored }
        let current = layout
        let items: [SidebarItem] = current.sections.filter { !$0.hidden && !$0.isCollapsed }.flatMap { section in
            var items = current.links(in: section.id).filter { !current.isHidden($0) && session.sidebarLinkAvailable($0) }.map { $0.presentation.destination }
            if section.id == SidebarGroup.sharing.rawValue, session.sharing.partnersAvailable {
                items += session.sharing.receivedPartners.filter { !current.isDynamicItemHidden(session.sidebarItemKey("partner:" + $0.id)) }.map { .partner($0.id) }
            }
            if section.listsAlbums {
                items += session.sidebarAlbums(in: section.id, layout: current).map { .album($0.id) }
            }
            return items
        }
        guard !items.isEmpty else { return .ignored }
        let index = selection.flatMap { items.firstIndex(of: $0) } ?? (offset > 0 ? -1 : items.count)
        let next = max(0, min(items.count - 1, index + offset))
        selection = items[next]
        scroll.scrollTo(items[next])
        return .handled
    }

    /// Fixed counts, like the system's Recent items setting. A count saved by an earlier version stays listed.
    private func albumLimitPicker(in sectionID: String, layout: SidebarLayout) -> some View {
        let limit = layout.albumLimit(in: sectionID)
        return Picker("Show", selection: Binding(get: { limit }, set: { value in update { $0.setAlbumLimit(value, in: sectionID) } })) {
            Text("All Albums").tag(Int?.none)
            Divider()
            ForEach(Set([5, 10, 15, 20, 30, 50] + (limit.map { [$0] } ?? [])).sorted(), id: \.self) { count in
                Text("\(count) Albums").tag(Int?.some(count))
            }
        }
    }

    private func albumSortPicker(in sectionID: String, layout: SidebarLayout) -> some View {
        Picker("Sort By", selection: Binding(get: { layout.albumSortBy(in: sectionID) },
                                             set: { value in update { $0.setAlbumSorting(value.rawValue, in: sectionID) } })) {
            ForEach(AlbumsSortBy.allCases) { Text($0.title).tag($0) }
        }
    }

    private func update(_ change: (inout SidebarLayout) -> Void) {
        var updated = layout
        change(&updated)
        storedLayout = updated.stored
    }
}

extension LibrarySession {
    func sidebarItemKey(_ item: String) -> String {
        client.serverURL.absoluteString + "|" + (user?.id ?? "") + "|" + item
    }

    /// Hidden albums are skipped before the limit applies, so the next album takes their place.
    func sidebarAlbums(in sectionID: String, layout: SidebarLayout) -> [Album] {
        let shown = albums.filter {
            $0.shared == (sectionID == SidebarGroup.sharedAlbums.rawValue) && !layout.isDynamicItemHidden(sidebarItemKey("album:" + $0.id))
        }
        return AlbumsArrangement.sidebar(shown, sortBy: layout.albumSortBy(in: sectionID), limit: layout.albumLimit(in: sectionID))
    }

    func sidebarAlbumsTruncated(in sectionID: String, layout: SidebarLayout) -> Bool {
        guard let limit = layout.albumLimit(in: sectionID) else { return false }
        return albums.count(where: {
            $0.shared == (sectionID == SidebarGroup.sharedAlbums.rawValue) && !layout.isDynamicItemHidden(sidebarItemKey("album:" + $0.id))
        }) > limit
    }

    func sidebarLinkAvailable(_ link: SidebarLink) -> Bool {
        switch link {
        case .people: features.facialRecognition
        case .map: features.map
        case .memories: services.explorePreferences?.memories?.enabled == true
        case .tags: services.explorePreferences?.tags?.enabled == true
        case .folders: services.explorePreferences?.folders?.enabled == true
        case .sharedLinks: sharing.linksAvailable
        case .partners: sharing.partnersAvailable
        case .duplicates: features.duplicateDetection == true
        case .trash: features.trash
        default: true
        }
    }
}

extension SidebarLayout {
    /// Album sections list recently changed albums first unless another sort is chosen.
    func albumSortBy(in sectionID: String) -> AlbumsSortBy {
        albumSorting(in: sectionID).flatMap(AlbumsSortBy.init(rawValue:)) ?? .dateModified
    }
}
