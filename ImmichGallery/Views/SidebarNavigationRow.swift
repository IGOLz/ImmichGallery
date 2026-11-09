import SwiftUI

extension SidebarGroup {
    var title: LocalizedStringKey {
        switch self {
        case .photos: "Photos"
        case .explore: "Explore"
        case .collections: "Collections"
        case .sharing: "Sharing"
        case .utilities: "Utilities"
        case .myAlbums: "My Albums"
        case .sharedAlbums: "Shared Albums"
        }
    }
}

extension SidebarSection {
    var label: Text {
        if let group = SidebarGroup(rawValue: id) { Text(group.title) }
        else { Text(verbatim: name ?? "") }
    }
}

extension SidebarLink {
    var presentation: (title: LocalizedStringKey, icon: String, destination: SidebarItem) {
        switch self {
        case .search: ("Search", "magnifyingglass", .search)
        case .library: ("Library", "photo.on.rectangle", .library)
        case .favorites: ("Favorites", "heart", .favorites)
        case .videos: ("Videos", "video", .videos)
        case .map: ("Map", "map", .explore(.map))
        case .places: ("Places", "globe.europe.africa", .explore(.places))
        case .memories: ("Memories", "sparkles.rectangle.stack", .explore(.memories))
        case .tags: ("Tags", "tag", .explore(.tags))
        case .folders: ("Folders", "folder", .explore(.folders))
        case .albums: ("Albums", "rectangle.stack", .albums)
        case .people: ("People", "person.crop.square", .people)
        case .sharedLinks: ("Shared Links", "link", .sharedLinks)
        case .partners: ("Partner Sharing", "person.2", .partners)
        case .duplicates: ("Duplicates", "square.on.square", .duplicates)
        case .largeFiles: ("Large Files", "externaldrive", .largeFiles)
        case .geolocation: ("Assign Location", "mappin.and.ellipse", .geolocation)
        case .archive: ("Archive", "archivebox", .archive)
        case .trash: ("Recently Deleted", "trash", .trash)
        case .locked: ("Locked Folder", "lock", .explore(.locked))
        }
    }
}

struct SidebarNavigationRow: View {
    let link: SidebarLink
    let sectionID: String
    @Binding var layout: String
    let visibleLinks: [SidebarLink]
    let customize: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SidebarNavigationLabel(link: link)
            .contextMenu {
                Button("Move Up") { shift(by: -1) }
                    .disabled(visibleLinks.first == link)
                Button("Move Down") { shift(by: 1) }
                    .disabled(visibleLinks.last == link)
                Menu("Move to Section") {
                    ForEach(SidebarLayout(stored: layout).sections.filter { !$0.hidden && $0.id != sectionID }) { destination in
                        Button { move(link, to: destination.id) } label: { destination.label }
                    }
                }
                Divider()
                Button("Hide from Sidebar") {
                    var updated = SidebarLayout(stored: layout)
                    updated.setHidden(true, link: link)
                    layout = updated.stored
                }
                Button("Customize Sidebar…", action: customize)
            }
    }

    private func shift(by offset: Int) {
        guard let index = visibleLinks.firstIndex(of: link), visibleLinks.indices.contains(index + offset) else { return }
        move(link, to: sectionID, relativeTo: visibleLinks[index + offset], after: offset > 0)
    }

    @discardableResult
    private func move(_ source: SidebarLink, to sectionID: String, relativeTo target: SidebarLink? = nil, after: Bool = false) -> Bool {
        var updated = SidebarLayout(stored: layout)
        guard updated.move(source, to: sectionID, relativeTo: target, after: after) else { return false }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { layout = updated.stored }
        return true
    }
}

struct SidebarNavigationLabel: View {
    let link: SidebarLink
    var body: some View {
        Label(link.presentation.title, systemImage: link.presentation.icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct SidebarSelectionRow<Content: View>: View {
    let item: SidebarItem
    @Binding var selection: SidebarItem?
    let onReselect: (() -> Void)?
    let content: Content
    @Environment(\.controlActiveState) private var activeState

    init(item: SidebarItem, selection: Binding<SidebarItem?>, onReselect: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.item = item
        self._selection = selection
        self.onReselect = onReselect
        self.content = content()
    }

    var body: some View {
        Button {
            if selection == item { onReselect?() }
            else { selection = item }
        } label: {
            SidebarRowContent(selected: selection == item, active: activeState == .key) { content }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
    }
}

