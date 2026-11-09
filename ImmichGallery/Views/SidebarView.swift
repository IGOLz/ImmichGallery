import SwiftUI

struct SidebarView: View {
    @Environment(LibrarySession.self) private var session
    @Binding var selection: SidebarItem?
    @AppStorage("sidebarLayout") private var storedLayout = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var customizing: Bool
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
    @GestureState private var gestureActive = false
    @FocusState private var sidebarFocused: Bool

    private var focusedSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { selection = $0; sidebarFocused = true })
    }

    private var layout: SidebarLayout { SidebarLayout(stored: displayedLayout) }

    var body: some View {
        let layout = self.layout
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(layout.sections.filter { !$0.hidden }) { section in
                            let links = layout.links(in: section.id).filter { !layout.isHidden($0) && session.sidebarLinkAvailable($0) }
                            LazyVStack(alignment: .leading, spacing: 0) {
                                section.label
                                    .accessibilityAddTraits(.isHeader)
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .modifier(SidebarDropRegion(target: SidebarDropTarget(sectionID: section.id), frames: $frames))
                                    .contextMenu {
                                        if section.listsAlbums {
                                            albumOptions(in: section.id, layout: layout)
                                            Divider()
                                        }
                                        Button("Hide Section") { update { $0.setSectionHidden(true, id: section.id) } }
                                        Button("Customize Sidebar…") { customizing = true }
                                    }
                                ForEach(links, id: \.self) { link in
                                    SidebarSelectionRow(item: link.presentation.destination, selection: focusedSelection) {
                                        SidebarNavigationRow(link: link, sectionID: section.id, layout: $storedLayout,
                                                             visibleLinks: links, customize: { customizing = true })
                                    }
                                    .opacity(settling && dragging == link ? 0 : 1)
                                    .modifier(SidebarDropRegion(target: SidebarDropTarget(sectionID: section.id, link: link), frames: $frames))
                                    .highPriorityGesture(dragGesture(link: link, sectionID: section.id))
                                    .id(link.presentation.destination)
                                }
                                if section.id == SidebarGroup.sharing.rawValue, session.sharing.partnersAvailable {
                                    ForEach(session.sharing.receivedPartners.filter { !layout.isDynamicItemHidden(session.sidebarItemKey("partner:" + $0.id)) }) { partner in
                                        SidebarSelectionRow(item: .partner(partner.id), selection: focusedSelection) {
                                            Label(partner.name, systemImage: "person.2")
                                        }
                                        .contextMenu {
                                            Button("Hide from Sidebar") {
                                                update { $0.setDynamicItemHidden(true, key: session.sidebarItemKey("partner:" + partner.id)) }
                                            }
                                        }
                                        .id(SidebarItem.partner(partner.id))
                                    }
                                }
                                if section.listsAlbums {
                                    AlbumSidebarRows(shared: section.id == SidebarGroup.sharedAlbums.rawValue, storedLayout: $storedLayout, selection: focusedSelection)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .coordinateSpace(name: "sidebarDrag")
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = CGRect(origin: .zero, size: $0) }
                .overlay {
                    ZStack(alignment: .topLeading) {
                        if let dragging {
                            SidebarFloatingPreview(selected: selection == dragging.presentation.destination, state: dragPreview) {
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
                    guard dragging != nil, !settling else { return .ignored }
                    dragging = nil
                    insertion = nil
                    dragCancelled = true
                    return .handled
                }
                .onChange(of: gestureActive) { _, active in if !active && !settling { clearDrag() } }
                .onKeyPress(.upArrow) { navigate(by: -1, scroll: proxy) }
                .onKeyPress(.downArrow) { navigate(by: 1, scroll: proxy) }
            }
            Divider()
            Button { customizing = true } label: {
                Label("Customize Sidebar…", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .onChange(of: storedLayout, initial: true) { _, value in
            guard displayedLayout != value else { return }
            withAnimation(reorderAnimation) { displayedLayout = value }
        }
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
        guard session.sidebarLinkAvailable(source), !current.isHidden(source),
              let position = SidebarDropPosition.resolve(at: point, in: viewport, targets: frames) else { return nil }
        let target = position.target.link ?? current.links(in: position.target.sectionID).first { !current.isHidden($0) && session.sidebarLinkAvailable($0) }
        var updated = current
        guard updated.move(source, to: position.target.sectionID, relativeTo: target, after: position.target.link != nil && position.edge == .after) else { return nil }
        return (position, updated)
    }

    private func navigate(by offset: Int, scroll: ScrollViewProxy) -> KeyPress.Result {
        let current = layout
        let items: [SidebarItem] = current.sections.filter { !$0.hidden }.flatMap { section in
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

    /// Album sections offer the same counts as the system's recent items setting, plus any count chosen in Customize Sidebar.
    @ViewBuilder
    private func albumOptions(in sectionID: String, layout: SidebarLayout) -> some View {
        let limit = layout.albumLimit(in: sectionID)
        Picker("Show", selection: Binding(get: { limit }, set: { value in update { $0.setAlbumLimit(value, in: sectionID) } })) {
            Text("All Albums").tag(Int?.none)
            Divider()
            ForEach(Set([5, 10, 15, 20, 30, 50] + (limit.map { [$0] } ?? [])).sorted(), id: \.self) { count in
                Text("\(count) Albums").tag(Int?.some(count))
            }
        }
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
