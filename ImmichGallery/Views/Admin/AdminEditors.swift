import SwiftUI

struct AdminUserEditor: View {
    let model: AdminModel
    let user: AdminUser?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var password = ""
    @State private var quota: String
    @State private var isAdmin: Bool
    @State private var shouldChangePassword: Bool

    init(model: AdminModel, user: AdminUser?) {
        self.model = model; self.user = user
        _name = State(initialValue: user?.name ?? "")
        _email = State(initialValue: user?.email ?? "")
        _quota = State(initialValue: AdminQuota.text(from: user?.quotaSizeInBytes))
        _isAdmin = State(initialValue: user?.isAdmin ?? false)
        _shouldChangePassword = State(initialValue: user?.shouldChangePassword ?? true)
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && email.contains("@") &&
        (user != nil || !password.isEmpty) &&
        (quota.isEmpty || AdminQuota.bytes(from: quota) != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(user == nil ? "New User" : "Edit User").font(.title2)
            Form {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                if user?.id != model.session.user?.id {
                    SecureField(user == nil ? "Password" : "New password (leave blank to keep)", text: $password)
                }
                TextField("Quota in GiB (blank for unlimited)", text: $quota)
                Toggle("Administrator", isOn: $isAdmin)
                Toggle("Require password change at next login", isOn: $shouldChangePassword)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        let input = AdminUserInput(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email.trimmingCharacters(in: .whitespacesAndNewlines), isAdmin: isAdmin, password: password.isEmpty ? nil : password, shouldChangePassword: shouldChangePassword, quotaSizeInBytes: AdminQuota.bytes(from: quota))
                        if await model.perform({ try await model.client.adminSaveUser(id: user?.id, input: input) }) { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).disabled(!valid || model.busy)
            }
        }.padding(24).frame(width: 520).disabled(model.busy)
    }
}

struct AdminLibraryEditor: View {
    let model: AdminModel
    let library: AdminLibrary?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var owner: String
    @State private var paths: String
    @State private var exclusions: String
    @State private var validation: String?

    init(model: AdminModel, library: AdminLibrary?) {
        self.model = model; self.library = library
        _name = State(initialValue: library?.name ?? "")
        _owner = State(initialValue: library?.ownerId ?? model.users.first(where: { !$0.isDeleted })?.id ?? "")
        _paths = State(initialValue: library?.importPaths.joined(separator: "\n") ?? "")
        _exclusions = State(initialValue: library?.exclusionPatterns.joined(separator: "\n") ?? "")
    }
    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var input: AdminLibraryInput {
        .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), ownerId: library == nil ? owner : nil, importPaths: lines(paths), exclusionPatterns: lines(exclusions))
    }
    private var valid: Bool {
        !input.name.isEmpty && !owner.isEmpty && input.importPaths.count <= 128 && input.exclusionPatterns.count <= 128
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(library == nil ? "New External Library" : "Edit External Library").font(.title2)
            Form {
                TextField("Name", text: $name)
                if library == nil {
                    Picker("Owner", selection: $owner) {
                        ForEach(model.users.filter { !$0.isDeleted }) { user in Text("\(user.name) · \(user.email)").tag(user.id) }
                    }
                }
                Text("Use paths on the Immich server, one per line. Up to 128 paths and exclusion patterns.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Import paths")
                TextEditor(text: $paths).font(.system(.body, design: .monospaced)).frame(height: 90).border(.separator)
                Text("Exclusion patterns")
                TextEditor(text: $exclusions).font(.system(.body, design: .monospaced)).frame(height: 75).border(.separator)
                if let validation { ScrollView { Text(validation).textSelection(.enabled) }.frame(maxHeight: 100) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            HStack {
                if let library {
                    Button("Validate Paths") {
                        Task { await model.perform {
                            let result = try await model.client.adminValidateLibrary(library.id, input: input)
                            validation = result.readable
                        } }
                    }.disabled(!valid || model.busy)
                } else {
                    Text("Save the library before validating its paths.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { if await model.perform({ try await model.client.adminSaveLibrary(id: library?.id, input: input) }) { dismiss() } }
                }.keyboardShortcut(.defaultAction).disabled(!valid || model.busy)
            }
        }.padding(24).frame(width: 600).disabled(model.busy)
    }
}
