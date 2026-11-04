import SwiftUI

struct PeopleView: View {
    @Environment(LibrarySession.self) private var session
    @State private var people: [Person] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var error: String?

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
                                .onAppear { if person.id == people.last?.id { Task { await loadMore() } } }
                        }
                    }
                    .padding(20)
                }
                .fastWheelScrolling()
            }
        }
        .navigationTitle("People")
        .navigationDestination(for: Person.self) { person in
            AssetGridContainer(source: .person(person.id),
                               title: person.name.isEmpty ? Text("Unnamed Person") : Text(verbatim: person.name))
        }
        .task { if people.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.client.people(page: page)
            let known = Set(people.map(\.id))
            people += response.people.filter { !$0.isHidden && !known.contains($0.id) }
            hasMore = response.hasNextPage ?? false
            page += 1
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
            hasMore = false
        }
    }
}

private struct PersonCell: View {
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
            Text(person.name.isEmpty ? String(localized: "Add Name") : person.name)
                .font(.callout)
                .foregroundStyle(person.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .task(id: person.id) { image = await session.pipeline.personThumbnail(person.id) }
    }
}
