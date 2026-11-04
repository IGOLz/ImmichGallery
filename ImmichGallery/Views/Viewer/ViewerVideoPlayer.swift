import AVKit
import SwiftUI

struct ViewerVideoOptions: View {
    @AppStorage("viewer.videoLoop") private var loop = false
    @AppStorage("viewer.videoSpeed") private var speed = 1.0
    var body: some View {
        Menu {
            Toggle("Loop Video", isOn: $loop)
            Picker("Playback Speed", selection: $speed) {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { Text("\($0.formatted())×").tag($0) }
            }
        } label: { Label("Video Options", systemImage: "slider.horizontal.3") }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
