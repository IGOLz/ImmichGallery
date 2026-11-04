import SwiftUI

struct SearchView: View {
    @Environment(LibrarySession.self) private var session
    let text: String
    var chooseText: (String) -> Void = { _ in }
    @State private var query = SearchQuery()
    @State private var draft = SearchQuery()
    @Binding var showFilters: Bool
    @State private var ratingsEnabled = false
    @State private var history = SearchHistory()
    @State private var explore: [SearchExploreGroup] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Search mode", selection: $query.mode) {
                    ForEach(SearchMode.allCases.filter { ($0 != .context || session.features.smartSearch) && ($0 != .ocr || session.features.ocr) }) { mode in
                        Text(String(localized: mode.title)).tag(mode)
                    }
                }
                .frame(width: 230)
                Button { draft = query; showFilters = true } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                }
                Spacer()
                Menu("Recent Searches") {
                    ForEach(Array(history.entries.enumerated()), id: \.offset) { _, entry in
                        Button(([entry.text] + entry.chips).filter { !$0.isEmpty }.joined(separator: ", ")) { query = entry; query.clampMode(smartEnabled: session.features.smartSearch, ocrEnabled: session.features.ocr); chooseText(entry.text) }
                    }
                    Divider()
                    Button("Clear History", role: .destructive) { history.clear() }
                }
                .disabled(history.entries.isEmpty)
            }
            .padding(12)
            if !query.chips.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(query.filterChips, id: \.id) { chip in
                            HStack(spacing: 4) {
                                Button(chip.title) { draft = query; showFilters = true }
                                Button { query.remove(chip.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .accessibilityLabel("Remove \(chip.title) filter")
                            }
                            .buttonStyle(.plain).padding(6).background(.quaternary, in: Capsule())
                        }
                        Button("Clear Filters") {
                            let text = query.text; let mode = query.mode
                            query = SearchQuery(); query.text = text; query.mode = mode
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
            Divider()
            if query.text.isEmpty && query.chips.isEmpty {
                ContentUnavailableView("Search Your Photos", systemImage: "magnifyingglass", description: Text("Enter text in the toolbar or choose filters."))
                if !explore.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(explore, id: \.fieldName) { group in
                                ForEach(group.items.prefix(12), id: \.value) { item in
                                    Button(item.value) {
                                        if group.fieldName == "exifInfo.city" { query.city = item.value }
                                        else { query.text = item.value }
                                    }
                                }
                            }
                        }.padding()
                    }
                }
            } else {
                AssetGridContainer(source: .filteredSearch(query), title: Text("Search"))
            }
        }
        .navigationTitle("Search")
        .navigationSubtitle(query.text)
        .onChange(of: showFilters) { _, showing in if showing { draft = query } }
        .sheet(isPresented: $showFilters) {
            SearchFiltersView(query: $draft, ratingsEnabled: ratingsEnabled) {
                query = draft; showFilters = false
            }
        }
        .task {
            query.text = text
            query.clampMode(smartEnabled: session.features.smartSearch, ocrEnabled: session.features.ocr)
            if showFilters { draft = query }
            history.load(session: session)
            history.remember(query)
            async let preferences = try? session.client.searchPreferences()
            async let suggestions = try? session.client.searchExplore()
            ratingsEnabled = await preferences?.ratings?.enabled ?? false
            // Explore is places in v3.3.5; only expose fields we can search accurately.
            explore = await suggestions?.filter { $0.fieldName == "exifInfo.city" } ?? []
        }
        .onChange(of: text) { _, value in query.text = value }
        .onChange(of: query) { _, value in history.remember(value) }
    }
}

struct SearchFieldSuggestions: View {
    @Environment(LibrarySession.self) private var session
    let text: String
    @State private var history = SearchHistory()

    private var completions: [String] {
        var seen: Set<String> = []
        return Array(history.entries.compactMap { entry in
            guard !entry.text.isEmpty, text.isEmpty || entry.text.localizedCaseInsensitiveContains(text),
                  seen.insert(entry.text).inserted else { return nil as String? }
            return entry.text
        }.prefix(8))
    }

    var body: some View {
        ForEach(completions, id: \.self) { text in
            Text(text).searchCompletion(text)
        }
        .onAppear { history.load(session: session) }
    }
}
