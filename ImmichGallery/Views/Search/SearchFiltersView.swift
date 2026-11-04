import SwiftUI

struct SearchFiltersView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Binding var query: SearchQuery
    let ratingsEnabled: Bool
    let apply: () -> Void
    @State private var people: [Person] = []
    @State private var page = 1
    @State private var hasMorePeople = true
    @State private var loadingPeople = false
    @State private var peopleError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Search Filters").font(.title2.bold())
                Spacer()
                Button("Reset") {
                    let text = query.text; let mode = query.mode
                    query = SearchQuery(); query.text = text; query.mode = mode
                }
            }.padding()
            Form {
                if session.features.facialRecognition {
                    Section("People") {
                        ScrollView(.horizontal) {
                            LazyHStack {
                                ForEach(people) { person in
                                    SearchPersonButton(person: person, selected: query.personIDs.contains(person.id)) {
                                        if !query.personIDs.insert(person.id).inserted { query.personIDs.remove(person.id) }
                                    }
                                }
                                if hasMorePeople {
                                    Button("Load More") { Task { await loadPeople() } }.disabled(loadingPeople)
                                }
                            }.padding(.vertical, 4)
                        }.frame(height: 90)
                        if let peopleError { Text(peopleError).foregroundStyle(.secondary) }
                    }
                }
                Section("Location") {
                    SearchSuggestionField(title: "Country", type: "country", value: $query.country, filters: query)
                    SearchSuggestionField(title: "State", type: "state", value: $query.state, filters: query)
                    SearchSuggestionField(title: "City", type: "city", value: $query.city, filters: query)
                }
                Section("Camera") {
                    SearchSuggestionField(title: "Make", type: "camera-make", value: $query.make, filters: query)
                    SearchSuggestionField(title: "Model", type: "camera-model", value: $query.model, filters: query)
                    SearchSuggestionField(title: "Lens", type: "camera-lens-model", value: $query.lensModel, filters: query)
                }
                Section("Date Taken") {
                    SearchDateFilter(title: "After", date: $query.takenAfter)
                    SearchDateFilter(title: "Before", date: $query.takenBefore)
                    if !query.validDates { Text("The start date must precede the end date.").foregroundStyle(.red) }
                }
                Section("Display") {
                    Picker("Media Type", selection: $query.mediaType) {
                        Text("All").tag(""); Text("Photos").tag("IMAGE"); Text("Videos").tag("VIDEO")
                    }
                    Toggle("Not in an album", isOn: $query.notInAlbum)
                    Toggle("Archived", isOn: $query.archived)
                    Toggle("Favorites", isOn: $query.favorites)
                    if ratingsEnabled {
                        Picker("Rating", selection: $query.rating) {
                            Text("Any").tag(nil as Int?)
                            ForEach(1...5, id: \.self) { Text("\($0) stars").tag(Optional($0)) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Search", action: apply).keyboardShortcut(.defaultAction).disabled(!query.validDates)
            }.padding()
        }
        .frame(width: 560, height: 680)
        .task { if session.features.facialRecognition { await loadPeople() } }
        .onChange(of: query.country) { query.state = ""; query.city = "" }
        .onChange(of: query.state) { query.city = "" }
        .onChange(of: query.make) { query.model = ""; query.lensModel = "" }
        .onChange(of: query.model) { query.lensModel = "" }
    }

    private func loadPeople() async {
        guard !loadingPeople, hasMorePeople else { return }
        loadingPeople = true
        defer { loadingPeople = false }
        do {
            let result = try await session.client.people(page: page)
            let known = Set(people.map(\.id))
            people += result.people.filter { !known.contains($0.id) }
            hasMorePeople = result.hasNextPage ?? (result.people.count == 500)
            page += 1; peopleError = nil
        } catch { session.handle(error); peopleError = error.localizedDescription }
    }
}

private struct SearchSuggestionField: View {
    @Environment(LibrarySession.self) private var session
    let title: String
    let type: String
    @Binding var value: String
    let filters: SearchQuery
    @State private var suggestions: [String] = []
    @State private var unavailable = false
    @State private var errorMessage: String?

    private var dependencies: [String] {
        [type, type == "state" || type == "city" ? filters.country : "", type == "city" ? filters.state : "",
         type == "camera-model" || type == "camera-lens-model" ? filters.make : "",
         type == "camera-lens-model" ? filters.model : ""]
    }

    var body: some View {
        HStack {
            TextField(title, text: $value)
            if !unavailable {
                Menu {
                    Button("Any") { value = "" }
                    ForEach(suggestions.filter { value.isEmpty || $0.localizedCaseInsensitiveContains(value) }, id: \.self) { suggestion in
                        Button(suggestion) { value = suggestion }
                    }
                    if let errorMessage { Text(errorMessage) }
                } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(title) suggestions")
            }
        }
        .task(id: dependencies) {
            do { suggestions = try await session.client.searchSuggestions(type, filters: filters); errorMessage = nil }
            catch ImmichError.http(404, _) { unavailable = true }
            catch { if !error.isCancellation { session.handle(error); errorMessage = error.localizedDescription } }
        }
    }
}

private struct SearchDateFilter: View {
    let title: String
    @Binding var date: Date?
    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { date != nil }, set: { date = $0 ? Date() : nil }))
            if date != nil {
                DatePicker(title, selection: Binding(get: { date ?? Date() }, set: { date = $0 }), displayedComponents: .date).labelsHidden()
            }
        }
    }
}

private struct SearchPersonButton: View {
    @Environment(LibrarySession.self) private var session
    let person: Person
    let selected: Bool
    let action: () -> Void
    @State private var image: CGImage?
    var body: some View {
        Button(action: action) {
            VStack {
                Circle().fill(.quaternary).overlay {
                    if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                }.clipShape(Circle()).frame(width: 48, height: 48)
                    .overlay { Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 3) }
                Text(person.name.isEmpty ? "Unnamed Person" : person.name).lineLimit(1).font(.caption)
            }.frame(width: 85)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: person.id) { image = await session.pipeline.personThumbnail(person.id) }
    }
}
