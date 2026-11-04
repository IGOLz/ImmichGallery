import SwiftUI
import UniformTypeIdentifiers

struct AccountSettingsView: View {
    let session: LibrarySession
    @State private var operation = AccountOperation()
    @State private var name = ""
    @State private var importing = false
    @State private var picture: NSImage?

    var body: some View {
        Form {
            Section("Profile") {
                HStack {
                    Group {
                        if let picture { Image(nsImage: picture).resizable().scaledToFill() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                    }
                    .frame(width: 64, height: 64).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(session.user?.email ?? "").textSelection(.enabled)
                        Text(session.client.serverURL.absoluteString).foregroundStyle(.secondary)
                    }
                }
                TextField("Name", text: $name)
                Button("Save Name") {
                    operation.run {
                        _ = try await session.client.updateAccountName(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        try await session.refreshAccountUser()
                        operation.message = "Name saved."
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == session.user?.name)
                HStack {
                    Button("Choose Profile Picture…") { importing = true }
                    Button("Remove Picture", role: .destructive) {
                        operation.run {
                            try await session.client.removeAccountPicture()
                            try await session.refreshAccountUser()
                            picture = nil
                        }
                    }.disabled(session.user?.profileImagePath?.isEmpty != false)
                }
            }
            Section("Storage") {
                if let used = session.user?.quotaUsageInBytes {
                    LabeledContent("Used", value: used.formatted(.byteCount(style: .file)))
                    if let quota = session.user?.quotaSizeInBytes, quota > 0 {
                        ProgressView(value: Double(used), total: Double(quota))
                        LabeledContent("Quota", value: quota.formatted(.byteCount(style: .file)))
                    } else { LabeledContent("Quota", value: "Unlimited") }
                } else { Text("Storage usage is unavailable.").foregroundStyle(.secondary) }
            }
            AccountOperationStatus(operation: operation)
        }
        .formStyle(.grouped)
        .disabled(operation.busy)
        .task {
            name = session.user?.name ?? ""
            await loadPicture()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            operation.run {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard let image = ImagePipeline.decode(data, maxPixelSize: 512),
                      let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                else { throw ImmichError.http(400, "Choose a supported image.") }
                try await session.client.uploadAccountPicture(jpeg)
                try await session.refreshAccountUser()
                await loadPicture()
            }
        }
    }

    private func loadPicture() async {
        guard let id = session.user?.id else { return }
        do {
            var request = try session.client.request("users/\(id)/profile-image")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let data = try await session.client.data(for: request)
            picture = NSImage(data: data)
        } catch { picture = nil }
    }
}

struct AccountOperationStatus: View {
    let operation: AccountOperation
    var body: some View {
        if operation.busy { ProgressView().controlSize(.small) }
        if let error = operation.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        if let message = operation.message { Text(message).foregroundStyle(.secondary) }
    }
}

struct AccountSettingsTabs: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        TabView {
            SettingsView().tabItem { Label("General", systemImage: "gearshape") }
            if let session = app.session {
                AccountSettingsView(session: session).id("profile-\(ObjectIdentifier(session))")
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
                AccountSecurityView(session: session).id("security-\(ObjectIdentifier(session))")
                    .tabItem { Label("Security", systemImage: "lock") }
                AccountPreferencesView(session: session).id("preferences-\(ObjectIdentifier(session))")
                    .tabItem { Label("Preferences", systemImage: "switch.2") }
            }
            AccountSwitcherView().tabItem { Label("Accounts", systemImage: "person.2") }
        }.frame(width: 640, height: 650)
    }
}

struct AccountSwitcherView: View {
    @Environment(AppModel.self) private var app
    @State private var operation = AccountOperation()
    @State private var adding = false
    @State private var entries = AccountVault.entries
    var body: some View {
        Form {
            Section("Saved Accounts") {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name + " · " + entry.email)
                            Text(entry.account.serverURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.session?.client.apiURL == entry.account.apiURL && app.session?.user?.id == entry.userID {
                            Image(systemName: "checkmark").accessibilityLabel("Current account")
                        } else {
                            Button("Switch") { operation.run { try await app.switchAccount(entry) } }
                        }
                        Button("Remove", role: .destructive) {
                            operation.run { try app.removeAccount(entry); entries = AccountVault.entries }
                        }.help("Remove saved credentials from this Mac")
                    }
                }
                Button("Add Account…") { adding = true }
            }
            AccountOperationStatus(operation: operation)
        }
        .formStyle(.grouped).disabled(operation.busy)
        .sheet(isPresented: $adding, onDismiss: { entries = AccountVault.entries }) {
            VStack {
                LoginView()
                Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction).padding()
            }.frame(width: 500, height: 600).environment(app)
                .onChange(of: app.session.map(ObjectIdentifier.init)) { _, _ in adding = false }
        }
    }
}

struct AccountMenu: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?
    var body: some View {
        Menu {
            Text(app.session?.user?.email ?? "Account")
            SettingsLink { Text("Account Settings…") }
            ForEach(AccountVault.entries) { entry in
                Button("\(entry.email) · \(entry.account.serverURL.host() ?? "")") {
                    Task { do { try await app.switchAccount(entry) } catch { self.error = error.localizedDescription } }
                }
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
        .alert("Could Not Switch Account", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
