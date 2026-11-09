import SwiftUI

struct SidebarCustomizationView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Binding var storedLayout: String
    @State private var newSectionName = ""
    @State private var renaming: SidebarSection?
    @State private var renamedSectionName = ""
    @State private var confirmingReset = false
    @State private var removing: SidebarSection?
    @State private var draftLayout: String
    @State private var initialLayout: String
    private var layout: SidebarLayout { SidebarLayout(stored: draftLayout) }

    init(storedLayout: Binding<String>) {
        _storedLayout = storedLayout
        _draftLayout = State(initialValue: storedLayout.wrappedValue)
        _initialLayout = State(initialValue: storedLayout.wrappedValue)
    }

    var body: some View {
        let layout = self.layout
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Customize Sidebar").font(.title2.bold())
                Text("Choose which items and sections appear on this Mac. Hiding them does not delete any photos or albums.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("New section name", text: $newSectionName).onSubmit(addSection)
                Button("Add Section", action: addSection)
                    .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(layout.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle(isOn: Binding(get: { !section.hidden }, set: { visible in
                                    update { $0.setSectionHidden(!visible, id: section.id) }
                                })) { section.label.font(.headline) }
                                .toggleStyle(.checkbox)
                                Spacer()
                                if section.isCustom {
                                    Button {
                                        renamedSectionName = section.name ?? ""
                                        renaming = section
                                    } label: { Image(systemName: "pencil") }
                                    .help("Rename Section")
                                    .accessibilityLabel("Rename Section")
                                    Button { removing = section } label: { Image(systemName: "trash") }
                                        .help("Delete Section…")
                                        .accessibilityLabel("Delete Section…")
                                }
                                Button { update { $0.shiftSection(id: section.id, by: -1) } } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(layout.sections.first?.id == section.id)
                                .accessibilityLabel(Text("Move Up") + Text(verbatim: ": ") + section.label)
                                Button { update { $0.shiftSection(id: section.id, by: 1) } } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(layout.sections.last?.id == section.id)
                                .accessibilityLabel(Text("Move Down") + Text(verbatim: ": ") + section.label)
                            }
                            .buttonStyle(.borderless)
                            .textCase(nil)
                            Divider()
                            if section.listsAlbums { albumOptions(in: section.id, layout: layout) }

                            ForEach(layout.links(in: section.id), id: \.self) { link in
                                HStack {
                                    Toggle(isOn: Binding(get: { !layout.isHidden(link) }, set: { visible in
                                        update { $0.setHidden(!visible, link: link) }
                                    })) {
                                        VStack(alignment: .leading) {
                                            Label(link.presentation.title, systemImage: link.presentation.icon)
                                            if !session.sidebarLinkAvailable(link) {
                                                Text("Unavailable on this server").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    Spacer()
                                    Menu {
                                        ForEach(layout.sections.filter { $0.id != section.id }) { destination in
                                            Button {
                                                update {
                                                    $0.move(link, to: destination.id)
                                                    $0.setSectionHidden(false, id: destination.id)
                                                    $0.setHidden(false, link: link)
                                                }
                                            } label: { destination.label }
                                        }
                                    } label: { Image(systemName: "folder.badge.arrow.forward") }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .accessibilityLabel(Text("Move to Section") + Text(verbatim: ": ") + Text(link.presentation.title))
                                    .help("Move to Section")
                                }
                            }
                            dynamicItems(in: section, layout: layout)
                            if layout.links(in: section.id).isEmpty && section.isCustom {
                                Text("Move items here using their Move to Section menu, or drag them into this section in the sidebar.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            HStack {
                Button("Reset Sidebar…") { confirmingReset = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 620)
        .onDisappear { if draftLayout != initialLayout { storedLayout = draftLayout } }
        .alert("Rename Section", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Section name", text: $renamedSectionName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let section = renaming { update { $0.renameSection(id: section.id, to: renamedSectionName) } }
                renaming = nil
            }
            .disabled(renamedSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete this custom section?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Delete Section", role: .destructive) {
                if let section = removing { update { $0.removeSection(id: section.id) } }
                removing = nil
            }
        } message: {
            Text("Items return to their default sections. Your photos and albums are not deleted.")
        }
        .confirmationDialog("Reset the sidebar?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Sidebar", role: .destructive) { draftLayout = "" }
        } message: {
            Text("This restores the default sections and item order, shows hidden items, and removes custom sections. Your photos and albums are not affected.")
        }
    }

    @ViewBuilder
    private func dynamicItems(in section: SidebarSection, layout: SidebarLayout) -> some View {
        if section.listsAlbums {
            let albums = session.albums.filter { $0.shared == (section.id == SidebarGroup.sharedAlbums.rawValue) }
            ForEach(AlbumsArrangement.sidebar(albums, sortBy: layout.albumSortBy(in: section.id), limit: nil)) { album in
                dynamicToggle(title: album.albumName, icon: "rectangle.stack", key: session.sidebarItemKey("album:" + album.id), layout: layout)
            }
        }
        if section.id == SidebarGroup.sharing.rawValue, session.sharing.partnersAvailable {
            ForEach(session.sharing.receivedPartners) { partner in
                dynamicToggle(title: partner.name, icon: "person.2", key: session.sidebarItemKey("partner:" + partner.id), layout: layout)
            }
        }
    }

    private func albumOptions(in sectionID: String, layout: SidebarLayout) -> some View {
        let limit = layout.albumLimit(in: sectionID)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Toggle("Show at most", isOn: Binding(get: { limit != nil }, set: { limited in
                    update { $0.setAlbumLimit(limited ? 10 : nil, in: sectionID) }
                }))
                .toggleStyle(.checkbox)
                Stepper(value: Binding(get: { limit ?? 10 }, set: { value in update { $0.setAlbumLimit(value, in: sectionID) } }), in: 1...99) {
                    Text("\(limit ?? 10) albums").monospacedDigit()
                }
                .disabled(limit == nil)
                Spacer()
                Picker("Sort By", selection: Binding(get: { layout.albumSortBy(in: sectionID) },
                                                     set: { value in update { $0.setAlbumSorting(value.rawValue, in: sectionID) } })) {
                    ForEach(AlbumsSortBy.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
            }
            if limit != nil {
                Text("Hidden albums are skipped, so the next album takes their place.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dynamicToggle(title: String, icon: String, key: String, layout: SidebarLayout) -> some View {
        Toggle(isOn: Binding(get: { !layout.isDynamicItemHidden(key) }, set: { visible in
            update { $0.setDynamicItemHidden(!visible, key: key) }
        })) { Label(title, systemImage: icon) }.toggleStyle(.checkbox)
    }

    private func addSection() {
        var updated = layout
        guard updated.addSection(named: newSectionName) != nil else { return }
        draftLayout = updated.stored
        newSectionName = ""
    }

    private func update(_ change: (inout SidebarLayout) -> Void) {
        var updated = layout
        change(&updated)
        draftLayout = updated.stored
    }
}
