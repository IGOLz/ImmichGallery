import SwiftUI

struct ExploreTagRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let removing: Bool
}

/// The list is built only after choosing a tag action, never while opening a context menu.
struct ExploreTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    let tags: [ExploreTag]
    let removing: Bool
    let apply: (ExploreTag) async throws -> Void
    @State var query = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    var matchingTags: [ExploreTag] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? tags : tags.filter { $0.value.localizedStandardContains(search) }
    }

    var body: some View {
        let matches = matchingTags
        return VStack(alignment: .leading, spacing: 16) {
            Text(removing ? "Remove Tag" : "Add Tag").font(.title2.bold())
            TextField("Search Tags", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
            List(matches) { tag in
                Button {
                    guard !busy else { return }
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await apply(tag); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Text(tag.value).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView("No Results", systemImage: "tag") }
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }
        .padding(24).frame(width: 440, height: 440)
        .interactiveDismissDisabled(busy)
        .onAppear { searchFocused = true }
        .alert("Tags", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
