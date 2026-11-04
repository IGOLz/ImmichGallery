import SwiftUI

extension Notification.Name {
    static let peopleChanged = Notification.Name("peopleChanged")
    static let personThumbnailChanged = Notification.Name("personThumbnailChanged")
}

struct PersonDetailView: View {
    @Environment(LibrarySession.self) private var session
    @State var person: Person
    @State private var count: Int?
    @State private var editing = false
    @State private var merging = false
    @State private var mergeCandidate: Person?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if session.gridModel(for: .person(person.id)).viewerID == nil {
                HStack(spacing: 20) {
                    PersonCell(person: person).frame(width: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.displayName).font(.largeTitle.bold())
                        if let birthday = person.birthday {
                            let age = Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0
                            Text("\(birthday.formatted(date: .abbreviated, time: .omitted)) · Age \(age)")
                                .foregroundStyle(.secondary)
                        }
                        if let count { Text("\(count) photos and videos").foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Menu {
                        Button("Edit Name and Birthday…") { editing = true }
                        Button(person.isFavorite == true ? "Unfavorite Person" : "Favorite Person") {
                            update(PersonEdit(isFavorite: person.isFavorite != true))
                        }
                        Button(person.isHidden ? "Unhide Person" : "Hide Person") {
                            update(PersonEdit(isHidden: !person.isHidden))
                        }
                        Button("Merge with Another Person…") { merging = true }
                    } label: { Label("Person Actions", systemImage: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(busy)
                }
                .padding(20)
                Divider()
            }
            AssetGridContainer(source: .person(person.id), title: Text(verbatim: person.displayName))
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .peopleChanged)) { _ in
            Task { await reload(); await session.gridModel(for: .person(person.id)).reload() }
        }
        .sheet(isPresented: $editing) {
            PersonEditSheet(person: person) { person = $0; changed() }
        }
        .sheet(isPresented: $merging) {
            PeoplePicker(title: "Merge into \(person.displayName)", excludedID: person.id) { mergeCandidate = $0 }
        }
        .confirmationDialog("Merge People?", isPresented: Binding(get: { mergeCandidate != nil }, set: { if !$0 { mergeCandidate = nil } })) {
            Button("Merge", role: .destructive) {
                guard let candidate = mergeCandidate else { return }
                mergeCandidate = nil
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await session.client.mergePeople(into: person.id, ids: [candidate.id])
                        changed()
                    } catch { report(error) }
                }
            }
        } message: {
            Text("All faces of \(mergeCandidate?.displayName ?? "this person") will move to \(person.displayName). This cannot be undone.")
        }
        .alert("People", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func update(_ edit: PersonEdit) {
        busy = true
        Task {
            defer { busy = false }
            do { person = try await session.client.editPerson(person.id, edit); changed() }
            catch { report(error) }
        }
    }
    private func reload() async {
        do {
            person = try await session.client.person(person.id)
            count = try await session.client.personStatistics(person.id).assets
        } catch { report(error) }
    }
    private func report(_ error: Error) { session.handle(error); self.error = error.localizedDescription }
    private func changed() {
        session.invalidateGrids()
        NotificationCenter.default.post(name: .peopleChanged, object: nil)
    }
}

struct PersonEditSheet: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let saved: (Person) -> Void
    @State private var name = ""
    @State private var birthday = Date.now
    @State private var hasBirthday = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Person").font(.headline)
            TextField("Name", text: $name)
            Toggle("Birthday", isOn: $hasBirthday)
            if hasBirthday { DatePicker("Date of Birth", selection: $birthday, in: ...Date.now, displayedComponents: .date) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let edit = PersonEdit(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  birthDate: hasBirthday ? Person.birthdayFormatter.string(from: birthday) : nil,
                                                  clearBirthDate: !hasBirthday)
                            saved(try await session.client.editPerson(person.id, edit))
                            dismiss()
                        } catch { session.handle(error); self.error = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction)
            }.disabled(busy)
        }
        .padding(24).frame(width: 380)
        .onAppear { name = person.name; birthday = person.birthday ?? .now; hasBirthday = person.birthday != nil }
    }
}

struct InspectorPeopleList: View {
    @Environment(LibrarySession.self) private var session
    let people: [AssetPerson]
    @State private var selected: Person?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if people.isEmpty { Text("No people").foregroundStyle(.secondary) }
            ForEach(people) { person in
                Button {
                    Task {
                        do { selected = try await session.client.person(person.id) }
                        catch { session.handle(error); self.error = error.localizedDescription }
                    }
                } label: { Label(person.name.isEmpty ? "Unnamed Person" : person.name, systemImage: "person.crop.circle") }
                    .buttonStyle(.link)
            }
        }
        .alert("People", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(item: $selected) { person in
            NavigationStack {
                PersonDetailView(person: person)
                    .toolbar { Button("Done") { selected = nil } }
            }.frame(minWidth: 850, minHeight: 650)
        }
    }
}
