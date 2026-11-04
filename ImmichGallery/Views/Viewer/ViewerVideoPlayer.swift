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

/// Authenticated range playback. Sound settings persist across assets and app launches.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    let headers: [String: String]
    var showsControls = true
    var playing = true
    var onFinished: (@MainActor @Sendable () -> Void)?
    @AppStorage("viewer.videoLoop") private var loop = false
    @AppStorage("viewer.videoSpeed") private var speed = 1.0

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .floating : .none
        view.allowsPictureInPicturePlayback = showsControls
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]))
        let player = AVPlayer(playerItem: item)
        player.isMuted = UserDefaults.standard.bool(forKey: "viewer.videoMuted")
        player.volume = UserDefaults.standard.object(forKey: "viewer.videoVolume") as? Float ?? 1
        view.player = player
        context.coordinator.observe(player, item: item)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFinished = onFinished
        coordinator.loop = loop && showsControls
        if coordinator.playing != playing || coordinator.speed != speed {
            coordinator.playing = playing
            coordinator.speed = speed
            if playing { view.player?.playImmediately(atRate: Float(speed)) } else { view.player?.pause() }
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        coordinator.stop()
        view.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var onFinished: (@MainActor @Sendable () -> Void)?
        var loop = false
        var playing: Bool?
        var speed = 0.0
        private var token: NSObjectProtocol?
        private var observations: [NSKeyValueObservation] = []

        func observe(_ player: AVPlayer, item: AVPlayerItem) {
            observations = [
                player.observe(\.volume, options: [.new]) { player, _ in UserDefaults.standard.set(player.volume, forKey: "viewer.videoVolume") },
                player.observe(\.isMuted, options: [.new]) { player, _ in UserDefaults.standard.set(player.isMuted, forKey: "viewer.videoMuted") }
            ]
            token = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self, weak player] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let onFinished = self.onFinished { onFinished() }
                    else if self.loop {
                        player?.seek(to: .zero)
                        player?.playImmediately(atRate: Float(self.speed))
                    }
                }
            }
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            observations = []
        }
    }
}
