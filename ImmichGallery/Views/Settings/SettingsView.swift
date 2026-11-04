import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var cacheSize: Int64 = 0
    @AppStorage(WheelScroll.multiplierKey) private var wheelMultiplier = WheelScroll.defaultMultiplier

    var body: some View {
        Form {
            if let session = app.session {
                Section("Account") {
                    LabeledContent("Name", value: session.user?.name ?? "—")
                    LabeledContent("Email", value: session.user?.email ?? "—")
                    if let used = session.user?.quotaUsageInBytes {
                        LabeledContent("Storage Used", value: used.formatted(.byteCount(style: .file)))
                    }
                }
                Section("Server") {
                    LabeledContent("Address", value: session.client.serverURL.absoluteString)
                    LabeledContent("Version", value: session.version?.description ?? "—")
                    LabeledContent("Signed in with") {
                        switch session.client.credential {
                        case .apiKey: Text("API Key")
                        default: Text("Password")
                        }
                    }
                }
                Section {
                    Slider(value: $wheelMultiplier, in: 1...8, step: 0.5) {
                        Text("Mouse Wheel Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                } footer: {
                    Text("How far each notch of a mouse wheel scrolls the photo grid. Trackpads are not affected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Image Cache", value: cacheSize.formatted(.byteCount(style: .file)))
                    HStack {
                        Button("Clear Cache") {
                            session.pipeline.removeAll()
                            cacheSize = 0
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
                    }
                }
            } else {
                Text("Not signed in.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            cacheSize = Int64(ImmichClient.sharedSession.configuration.urlCache?.currentDiskUsage ?? 0)
        }
    }
}
