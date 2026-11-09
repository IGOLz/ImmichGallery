import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var cacheSize: Int64 = 0
    @AppStorage(WheelScroll.multiplierKey) private var wheelMultiplier = WheelScroll.defaultMultiplier
    @AppStorage(HDRPhotos.enabledKey) private var showHDR = true

    var body: some View {
        Form {
            if let session = app.services {
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
                    Toggle("Show Photos in High Dynamic Range", isOn: $showHDR)
                } footer: {
                    Text("On an HDR display, photos with HDR highlights are shown at their full brightness. To find them, the viewer downloads the original of each photo you open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MacNotificationPreference()
                Section {
                    LabeledContent("Image Cache", value: cacheSize.formatted(.byteCount(style: .file)))
                    Button("Clear Cache") {
                        session.pipeline.removeAll()
                        session.metadata.imageRevision += 1
                        session.invalidateGrids()
                        cacheSize = 0
                    }
                }
            } else {
                Text("Not signed in.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
        .onAppear {
            cacheSize = Int64(app.services?.client.session.configuration.urlCache?.currentDiskUsage ?? 0)
        }
    }
}
