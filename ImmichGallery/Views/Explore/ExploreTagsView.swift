import SwiftUI

struct ExploreTagsView: View {
    @Environment(LibrarySession.self) private var session
    @State private var tags: [ExploreTag] = []
    @State private var editing: ExploreTag?
    @State private var deleting: ExploreTag?
    @State private var name = ""
    @State private var color = ""
    @State private var showingEditor = false
    @State private var error: String?
    var body: some View {
        List(tags) { tag in
            NavigationLink {
                AssetGridContainer(source: .explore(.tag(tag.id)), title: Text(tag.value))
            } label: { Label(tag.value, systemImage: "tag").foregroundStyle(tagColor(tag.color)) }
            .contextMenu {
                Button("Edit Tag…") { editing = tag; name = tag.name; color = tag.color ?? ""; showingEditor = true }
                Button("Delete Tag…", role: .destructive) { deleting = tag }
            }
        }
        .toolbar {
            Button { editing = nil; name = ""; color = ""; showingEditor = true } label: { Label("New Tag", systemImage: "plus") }
        }
        .task { await reload() }
        .sheet(isPresented: $showingEditor) {
            Form {
                TextField(editing == nil ? "Tag path (parent/child)" : "Name", text: $name)
                if editing != nil { TextField("Color (#RRGGBB, empty to clear)", text: $color) }
                HStack {
                    Button("Cancel", role: .cancel) { showingEditor = false }
                    Button("Save") {
                        Task {
                            do {
                                if let editing { try await session.client.exploreUpdateTag(editing, name: name, color: color) }
                                else { try await session.client.exploreCreateTag(name) }
                                showingEditor = false
                                await reload()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.keyboardShortcut(.defaultAction).disabled(!valid)
                }
            }.padding().frame(width: 380)
        }
        .confirmationDialog("Delete tag \(deleting?.value ?? "") and its child tags?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Tag", role: .destructive) {
                guard let tag = deleting else { return }
                Task { do { try await session.client.exploreDeleteTag(tag.id); await reload() } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("Photos are kept. Tag assignments are removed.") }
        .alert("Tags", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (editing == nil || !name.contains("/")) &&
        (color.isEmpty || color.range(of: "^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$", options: .regularExpression) != nil)
    }
    private func reload() async {
        do { tags = try await session.client.exploreTags().sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending } }
        catch { self.error = error.localizedDescription }
    }
    private func tagColor(_ hex: String?) -> Color {
        guard let hex, hex.count == 7, let value = UInt(hex.dropFirst(), radix: 16) else { return .primary }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct ExploreAssetActions: View {
    @Environment(LibrarySession.self) private var session
    let ids: [String]
    let model: AssetGridModel
    @State private var tags: [ExploreTag] = []
    @State private var enabled = false
    var body: some View {
        Menu("Tags") {
            if !enabled { Text("Enable Tags in Immich Account Settings") }
            ForEach(tags) { tag in
                Menu(tag.value) {
                    Button("Add Tag") { update(tag, remove: false) }
                    Button("Remove Tag") { update(tag, remove: true) }
                }
            }
        }.task {
            enabled = (try? await session.client.explorePreferences())?.tags?.enabled == true
            if enabled { tags = (try? await session.client.exploreTags()) ?? [] }
        }
        Button("Move to Locked Folder") {
            Task {
                do {
                    try await session.client.setVisibility(ids, "locked")
                    session.exploreRemoveFromGrids(Set(ids))
                    session.pipeline.removeAll()
                    session.invalidateGrids()
                    await model.reload()
                } catch { model.lastError = error.localizedDescription }
            }
        }
    }
    private func update(_ tag: ExploreTag, remove: Bool) {
        Task {
            do { try await session.client.exploreTagAssets(ids, tag: tag.id, remove: remove); session.invalidateGrids(); await model.reload() }
            catch { model.lastError = error.localizedDescription }
        }
    }
}
