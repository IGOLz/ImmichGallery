import SwiftUI

struct AccountPreferencesView: View {
    let session: LibrarySession
    @State private var draft = AccountPreferences()
    @State private var operation = AccountOperation()
    @State private var loaded = false

    var body: some View {
        Form {
            if loaded && !operation.unavailable {
                AccountFeaturePreference(title: "Memories", value: $draft.memories)
                AccountFeaturePreference(title: "Ratings", value: $draft.ratings)
                AccountFeaturePreference(title: "Folders", value: $draft.folders)
                AccountFeaturePreference(title: "Tags", value: $draft.tags)
                AccountFeaturePreference(title: "People", value: $draft.people)
                AccountFeaturePreference(title: "Shared Links", value: $draft.sharedLinks)
                if draft.memories?.duration != nil {
                    Stepper("Memory Duration: \(draft.memories?.duration ?? 5) seconds", value: Binding(
                        get: { draft.memories?.duration ?? 5 }, set: { draft.memories?.duration = $0 }), in: 1...60)
                }
                if draft.people != nil {
                    Stepper("Minimum Faces: \(draft.people?.minimumFaces ?? 1)", value: Binding(
                        get: { draft.people?.minimumFaces ?? 1 }, set: { draft.people?.minimumFaces = $0 }), in: 1...1000)
                    Picker("People Update Strategy", selection: Binding(
                        get: { draft.people?.updateStrategy ?? "self" }, set: { draft.people?.updateStrategy = $0 })) {
                        Text("Only This Person").tag("self")
                        Text("Everyone").tag("everyone")
                    }
                }
                if draft.albums != nil {
                    Picker("Default Album Order", selection: Binding(
                        get: { draft.albums?.defaultAssetOrder ?? "desc" }, set: { draft.albums?.defaultAssetOrder = $0 })) {
                        Text("Newest First").tag("desc")
                        Text("Oldest First").tag("asc")
                    }
                }
                if draft.download != nil {
                    Section("Downloads") {
                        TextField("Archive Size (GiB)", value: Binding(
                            get: { Double(draft.download?.archiveSize ?? 4_294_967_296) / 1_073_741_824 },
                            set: { if $0.isFinite { draft.download?.archiveSize = Int64(min(max($0, 0.01), 8192) * 1_073_741_824) } }), format: .number)
                        if draft.download?.includeEmbeddedVideos != nil {
                            Toggle("Include Embedded Videos", isOn: Binding(get: { draft.download?.includeEmbeddedVideos ?? false }, set: { draft.download?.includeEmbeddedVideos = $0 }))
                        }
                    }
                }
                if draft.emailNotifications != nil {
                    Section("Email Notifications") {
                        Toggle("Enable Email Notifications", isOn: Binding(get: { draft.emailNotifications?.enabled ?? false }, set: { draft.emailNotifications?.enabled = $0 }))
                        Toggle("Album Invitations", isOn: Binding(get: { draft.emailNotifications?.albumInvite ?? false }, set: { draft.emailNotifications?.albumInvite = $0 }))
                        Toggle("Album Updates", isOn: Binding(get: { draft.emailNotifications?.albumUpdate ?? false }, set: { draft.emailNotifications?.albumUpdate = $0 }))
                    }
                }
                if draft.cast?.gCastEnabled != nil {
                    Toggle("Google Cast", isOn: Binding(get: { draft.cast?.gCastEnabled ?? false }, set: { draft.cast?.gCastEnabled = $0 }))
                }
                if draft.recentlyAdded?.sidebarWeb != nil {
                    Toggle("Recently Added in Web Sidebar", isOn: Binding(get: { draft.recentlyAdded?.sidebarWeb ?? false }, set: { draft.recentlyAdded?.sidebarWeb = $0 }))
                }
                if draft.purchase?.showSupportBadge != nil {
                    Toggle("Show Support Badge", isOn: Binding(get: { draft.purchase?.showSupportBadge ?? false }, set: { draft.purchase?.showSupportBadge = $0 }))
                }
                Button("Save Preferences") {
                    operation.run {
                        session.setPreferences(try await session.client.updateAccountPreferences(draft))
                        draft = session.preferences ?? draft
                        operation.message = String(localized: "Preferences saved.")
                    }
                }
                Text("These preferences are stored on your Immich server. Web sidebar options affect the web client.").font(.caption).foregroundStyle(.secondary)
            }
            AccountOperationStatus(operation: operation)
        }
        .formStyle(.grouped).disabled(operation.busy)
        .task {
            operation.run(probe: true) {
                draft = try await session.client.accountPreferences()
                session.setPreferences(draft)
                loaded = true
            }
        }
    }
}

private struct AccountFeaturePreference: View {
    let title: String
    @Binding var value: AccountPreferences.Feature?
    var body: some View {
        if value != nil {
            Section(title) {
                if value?.enabled != nil {
                    Toggle("Enabled", isOn: Binding(get: { value?.enabled ?? false }, set: { value?.enabled = $0 }))
                }
                if value?.sidebarWeb != nil {
                    Toggle("Show in Web Sidebar", isOn: Binding(get: { value?.sidebarWeb ?? false }, set: { value?.sidebarWeb = $0 }))
                }
            }
        }
    }
}
