import SwiftUI

struct PeopleView: View {
    @Environment(LibrarySession.self) private var session
    @State private var people: [Person] = []
    @State private var showHidden = false
    @State private var revision = 0
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var requestID = UUID()
    @State private var error: String?
    @State private var editing: Person?
    @State private var merging: Person?
    @State private var mergePair: (target: Person, source: Person)?

    var body: some View {
        Group {
            if people.isEmpty && isLoading {
                ProgressView().controlSize(.large)
            } else if people.isEmpty {
                ContentUnavailableView("No People", systemImage: "person.crop.square",
                                       description: Text(error ?? String(localized: "People recognized by Immich appear here.")))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)], spacing: 20) {
                        ForEach(people) { person in
                            NavigationLink(value: person) { PersonCell(person: person) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename…") { editing = person }
                                    Button(person.isHidden ? "Unhide Person" : "Hide Person") {
                                        update(person, PersonEdit(isHidden: !person.isHidden))
                                    }
                                    Button("Merge…") { merging = person }
                                    Button(person.isFavorite == true ? "Unfavorite Person" : "Favorite Person") {
                                        update(person, PersonEdit(isFavorite: person.isFavorite != true))
                                    }
                                }
                                .onAppear { if person.id == people.last?.id { Task { await loadMore() } } }
                        }
                    }
                    .padding(20)
                }
                .fastWheelScrolling()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error {
                HStack {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") {
                        self.error = nil; hasMore = true
                        Task { await loadMore() }
                    }
                }.padding().background(.bar)
            }
        }
        .sheet(item: $editing) { person in
            PersonEditSheet(person: person) { _ in changed() }
        }
        .sheet(item: $merging) { person in
            PeoplePicker(title: "Merge into \(person.displayName)", excludedID: person.id) {
                mergePair = (person, $0)
            }
        }
        .confirmationDialog("Merge People?", isPresented: Binding(get: { mergePair != nil }, set: { if !$0 { mergePair = nil } })) {
            Button("Merge", role: .destructive) {
                guard let pair = mergePair else { return }
                mergePair = nil
                Task {
                    do {
                        try await session.client.mergePeople(into: pair.target.id, ids: [pair.source.id])
                        changed()
                    } catch { session.handle(error); self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("All faces of \(mergePair?.source.displayName ?? "this person") will move to \(mergePair?.target.displayName ?? "the selected person"). This cannot be undone.")
        }
        .navigationTitle("People")
        .navigationDestination(for: Person.self) { person in
            PersonDetailView(person: person)
        }
        .toolbar { Toggle(isOn: $showHidden) { Label("Show Hidden People", systemImage: "eye.slash") } }
        .onReceive(NotificationCenter.default.publisher(for: .peopleChanged)) { _ in revision += 1 }
        .task(id: "\(showHidden)-\(revision)") {
            requestID = UUID(); isLoading = false
            people = []; page = 1; hasMore = true; error = nil
            await loadMore()
        }
    }

    private func changed() {
        session.invalidateGrids()
        NotificationCenter.default.post(name: .peopleChanged, object: nil)
    }

    private func update(_ person: Person, _ edit: PersonEdit) {
        Task {
            do { _ = try await session.client.editPerson(person.id, edit); changed() }
            catch { session.handle(error); self.error = error.localizedDescription }
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let currentRequest = requestID
        isLoading = true
        defer { if currentRequest == requestID { isLoading = false } }
        do {
            let response = try await session.client.peoplePage(page: page, withHidden: showHidden)
            try Task.checkCancellation()
            guard currentRequest == requestID else { return }
            let known = Set(people.map(\.id))
            people += response.people.filter { (showHidden || !$0.isHidden) && !known.contains($0.id) }
            hasMore = response.hasNextPage ?? (!response.people.isEmpty && page * 100 < response.total)
            page += 1
        } catch is CancellationError {
        } catch {
            guard currentRequest == requestID else { return }
            session.handle(error)
            self.error = error.localizedDescription
            hasMore = false
        }
    }
}

struct PersonCell: View {
    @Environment(LibrarySession.self) private var session
    let person: Person
    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.quaternary)
                .overlay {
                    if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                }
                .clipShape(Circle())
                .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 4) {
                if person.isFavorite == true { Image(systemName: "heart.fill").foregroundStyle(.red) }
                if person.isHidden { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
            }.font(.caption)
            Text(person.name.isEmpty ? String(localized: "Add Name") : person.name)
                .font(.callout)
                .foregroundStyle(person.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .task(id: person.id) {
            image = await session.pipeline.personThumbnail(person.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .personThumbnailChanged)) { notification in
            guard notification.object as? String == person.id else { return }
            Task { image = await session.pipeline.personThumbnail(person.id) }
        }
    }
}
