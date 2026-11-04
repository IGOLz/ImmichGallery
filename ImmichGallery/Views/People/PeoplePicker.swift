import SwiftUI

struct PeoplePicker: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: String
    var excludedID: String?
    var allowsCreation = false
    let selected: (Person) async throws -> Void
    @State private var people: [Person] = []
    @State private var query = ""
    @State private var page = 1
    @State private var more = true
    @State private var busy = false
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            TextField("Search People", text: $query)
            List {
                ForEach(people.filter { $0.id != excludedID }) { person in
                    Button { choose(person) } label: {
                        HStack { PersonCell(person: person).frame(width: 52); Text(person.displayName); Spacer() }
                    }.buttonStyle(.plain)
                }
                if more { Button("Load More") { Task { await load() } }.disabled(loading) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if allowsCreation {
                    Button("Create Person") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                let person = try await session.client.createPerson(name: query.trimmingCharacters(in: .whitespacesAndNewlines))
                                // Keep the new person available if assignment fails, so Retry never creates duplicates.
                                people.insert(person, at: 0)
                                try await selected(person)
                                NotificationCenter.default.post(name: .peopleChanged, object: session.services)
                                dismiss()
                            } catch { session.handle(error); self.error = error.localizedDescription }
                        }
                    }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20).frame(width: 430, height: 520).disabled(busy)
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            requestID = UUID(); loading = false
            people = []; page = 1; more = true
            await load()
        }
    }
    private func choose(_ person: Person) {
        busy = true
        Task {
            defer { busy = false }
            do { try await selected(person); dismiss() }
            catch { session.handle(error); self.error = error.localizedDescription }
        }
    }
    private func load() async {
        guard !loading, more else { return }
        let currentRequest = requestID
        loading = true
        defer { if currentRequest == requestID { loading = false } }
        do {
            let response = try await session.client.peoplePage(page: page, withHidden: true, name: query.isEmpty ? nil : query)
            try Task.checkCancellation()
            guard currentRequest == requestID else { return }
            let known = Set(people.map(\.id))
            people += response.people.filter { !known.contains($0.id) }
            more = response.hasNextPage ?? (!response.people.isEmpty && page * 100 < response.total)
            page += 1
            error = nil
        } catch is CancellationError { }
        catch {
            guard currentRequest == requestID else { return }
            session.handle(error); self.error = error.localizedDescription
        }
    }
}
