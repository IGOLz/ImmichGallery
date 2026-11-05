import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct AccountSettingsView: View {
    let session: AccountServices
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
                        operation.message = String(localized: "Name saved.")
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines) == session.user?.name)
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
                        ProgressView(value: Double(min(max(used, 0), quota)), total: Double(quota))
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
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try accountProfileJPEG(url: url)
                }.value
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
    @State private var tab = "general"
    var body: some View {
        TabView(selection: $tab) {
            SettingsView().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            if let session = app.services {
                AccountSettingsView(session: session).id("profile-\(ObjectIdentifier(session))")
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("account")
                AccountSecurityView(session: session).id("security-\(ObjectIdentifier(session))")
                    .tabItem { Label("Security", systemImage: "lock") }.tag("security")
                AccountPreferencesView(session: session).id("preferences-\(ObjectIdentifier(session))")
                    .tabItem { Label("Preferences", systemImage: "switch.2") }.tag("preferences")
            }
            AccountSwitcherView().tabItem { Label("Accounts", systemImage: "person.2") }.tag("accounts")
            UpdateSettingsView().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }.tag("updates")
        }.frame(width: 640, height: tab == "general" ? 440 : tab == "updates" ? 320 : 650)
    }
}

struct AccountSwitcherView: View {
    @Environment(AppModel.self) private var app
    @State private var operation = AccountOperation()
    @State private var adding = false
    var body: some View {
        Form {
            Section("Saved Accounts") {
                ForEach(app.entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name + " · " + entry.email)
                            Text(entry.account.serverURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.currentAccountID == entry.id {
                            Image(systemName: "checkmark").accessibilityLabel("Current account")
                        } else {
                            Button("Switch") { operation.run { try await app.switchAccount(entry) } }
                        }
                        Button("Remove", role: .destructive) {
                            operation.run { try app.removeAccount(entry) }
                        }.help("Remove saved credentials from this Mac")
                    }
                }
                Button("Add Account…") { adding = true }
            }
            AccountOperationStatus(operation: operation)
        }
        .formStyle(.grouped).disabled(operation.busy || app.switching)
        .sheet(isPresented: $adding) {
            VStack {
                LoginView()
                Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction).padding()
            }.frame(width: 500, height: 600).environment(app)
                .onChange(of: app.services.map(ObjectIdentifier.init)) { _, _ in adding = false }
        }
    }
}

struct AccountMenu: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?
    @State private var adding = false
    var body: some View {
        Menu {
            Text(app.services?.user?.email ?? "Account")
            SettingsLink { Text("Account Settings…") }
            ForEach(app.entries) { entry in
                Button {
                    Task { do { try await app.switchAccount(entry) } catch { self.error = error.localizedDescription } }
                } label: {
                    if app.currentAccountID == entry.id {
                        Label("\(entry.email) · \(entry.account.serverURL.host() ?? "")", systemImage: "checkmark")
                    } else { Text("\(entry.email) · \(entry.account.serverURL.host() ?? "")") }
                }.disabled(app.currentAccountID == entry.id || app.switching)
            }
            Divider()
            Button("Add Account…") { adding = true }.disabled(app.switching)
            Button("Sign Out", role: .destructive) { Task { await app.signOut() } }.disabled(app.switching)
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
        .sheet(isPresented: $adding) {
            VStack {
                LoginView()
                Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction).padding()
            }.frame(width: 500, height: 600).environment(app)
                .onChange(of: app.services.map(ObjectIdentifier.init)) { _, _ in adding = false }
        }
        .alert("Could Not Switch Account", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

nonisolated func accountProfileJPEG(url: URL) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 50 * 1024 * 1024,
          let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
          ] as CFDictionary) else {
        throw ImmichError.http(400, String(localized: "Choose a supported image smaller than 50 MB."))
    }
    let side = min(image.width, image.height)
    guard let square = image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)) else {
        throw ImmichError.http(400, String(localized: "Could not crop the profile picture."))
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw ImmichError.http(400, String(localized: "Could not encode the profile picture."))
    }
    CGImageDestinationAddImage(destination, square, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImmichError.http(400, String(localized: "Could not encode the profile picture.")) }
    return data as Data
}
