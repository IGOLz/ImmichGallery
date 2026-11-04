import AVKit
import SwiftUI

/// Single-asset viewer shown in place of the grid (like double-clicking in Photos).
struct AssetViewer: View {
    @Environment(LibrarySession.self) private var session
    @Bindable var model: AssetGridModel
    let item: AssetItem
    @Binding var playLive: Bool
    let onDelete: ([String]) -> Void

    @Environment(\.viewerContext) private var viewer
    var isPresentation = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if !isPresentation { Color.black.opacity(0.92).ignoresSafeArea() }

            if viewer?.window != nil && !isPresentation {
                Color.black
            } else if item.isVideo {
                VideoPlayerView(url: session.client.videoURL(item.id), headers: session.client.credential?.headers ?? [:],
                                playing: viewer?.slideshow != true || viewer?.paused != true,
                                onFinished: videoFinished,
                                onProgress: { viewer?.videoStalledElapsed = 0 },
                                onFailed: { if viewer?.slideshow == true && viewer?.paused != true { viewer?.step(1) } })
                    .id("\(item.id)-\(viewer?.playbackGeneration ?? 0)")
                    .overlay(alignment: .topTrailing) { ViewerVideoOptions().padding()
                        .opacity(!isPresentation || viewer?.controlsVisible != false ? 1 : 0)
                        .allowsHitTesting(!isPresentation || viewer?.controlsVisible != false) }
                    .draggable(OriginalTransfer(id: item.id, isVideo: true, client: session.client))
            } else {
                ZoomableImage(item: item, rotation: viewer?.rotation ?? 0)
                    .id(item.id)
                if playLive, let videoID = item.livePhotoVideoID {
                    VideoPlayerView(
                        url: session.client.videoURL(videoID),
                        headers: session.client.credential?.headers ?? [:],
                        showsControls: false,
                        onFinished: { playLive = false })
                        .id(videoID)
                        .allowsHitTesting(false)
                }
            }

            if !isPresentation {
                HStack {
                    navButton("chevron.left", delta: -1)
                    Spacer()
                    navButton("chevron.right", delta: 1)
                }
                .padding(.horizontal, 16)
            }
        }
        .safeAreaInset(edge: .top) { AssetsStackButton(item: item, model: model).id(item.id) }
        .contextMenu {
            if !model.source.isPartner, model.source != .trash { // Explore
                Button("Move to Locked Folder") { Task { await model.moveToLockedFolder([item.id]) } }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(action: handleKey)
        .onExitCommand { if isPresentation { viewer?.close() } else { model.viewerID = nil } }
        .task(id: item.id) { await prefetchNeighbours() }
    }

    private var videoFinished: (@MainActor @Sendable () -> Void)? {
        guard let viewer, viewer.slideshow else { return nil }
        return { viewer.step(1) }
    }

    private func navButton(_ symbol: String, delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(0.9)
    }

    private func step(_ delta: Int) {
        if isPresentation { viewer?.step(delta); return }
        Task {
            if let next = await model.neighbor(of: item.id, delta: delta) {
                model.viewerID = next.id
                model.selection = [next.id]
            }
        }
    }

    private func prefetchNeighbours() async {
        for delta in [1, -1] {
            if let next = await (isPresentation ? viewer?.neighbor(of: item.id, delta: delta) : model.neighbor(of: item.id, delta: delta)), !next.isVideo {
                _ = await session.pipeline.thumbnail(next.id, size: .preview)
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if isPresentation {
            if press.key == .escape { viewer?.close(); return .handled }
            if press.key == .return { return .handled }
            if press.key == .space {
                if viewer?.slideshow == true { viewer?.paused.toggle() }
                return .handled
            }
        }
        switch press.key {
        case .leftArrow: step(-1)
        case .rightArrow: step(1)
        case .space where !item.isVideo, .escape, .return: model.viewerID = nil
        case .delete, .deleteForward:
            guard press.modifiers.contains(.command) else { return .ignored }
            onDelete([item.id])
        default:
            guard press.characters == "." else { return .ignored }
            Task { await model.toggleFavorite([item.id]) }
        }
        return .handled
    }
}

/// Shows the cached thumbnail instantly, then the preview, and fetches the original once the
/// user zooms in past 1×. Pinch or double-click to zoom, drag to pan.
private struct ZoomableImage: View {
    @Environment(LibrarySession.self) private var session
    let item: AssetItem
    let rotation: Int

    @State private var image: CGImage?
    @State private var hasOriginal = false
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geo in
            let swapsAxes = abs(rotation % 180) == 90
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .draggable(OriginalTransfer.self, item: scale * gestureScale <= 1
                                   ? OriginalTransfer(id: item.id, client: session.client) : nil)
                } else if let hash = item.thumbhash, let placeholder = ThumbHash.image(base64: hash) {
                    Image(decorative: placeholder, scale: 1)
                        .resizable()
                        .aspectRatio(item.ratio, contentMode: .fit)
                    ProgressView().controlSize(.large)
                }
            }
            .frame(width: swapsAxes ? geo.size.height : geo.size.width, height: swapsAxes ? geo.size.width : geo.size.height)
            .rotationEffect(.degrees(Double(rotation)))
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * gestureScale)
            .offset(offset)
            .overlay {
                if let image {
                    PeopleFaceOverlay(assetID: item.id, imageSize: CGSize(width: image.width, height: image.height),
                                      zoom: scale * gestureScale, offset: offset)
                }
            }
            .contentShape(Rectangle())
            .gesture(magnify)
            .simultaneousGesture(pan(in: geo.size), isEnabled: scale * gestureScale > 1)
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 }
                }
            }
        }
        .clipped()
        .task { await load() }
        .onChange(of: scale) { _, newValue in
            if newValue > 1.1 && !hasOriginal {
                hasOriginal = true
                Task { if let original = await session.pipeline.original(item.id, edited: true) { image = original } }
            }
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { gestureScale = $0.magnification }
            .onEnded { value in
                scale = min(8, max(1, scale * value.magnification))
                gestureScale = 1
                if scale == 1 { withAnimation(.snappy) { offset = .zero } }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard scale > 1 else { return }
                let start = dragStart ?? offset
                dragStart = start
                offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func load() async {
        let pipeline = session.pipeline
        image = pipeline.cachedThumbnail(item.id, size: .preview) ?? pipeline.cachedThumbnail(item.id, size: .thumbnail)
        if let preview = await pipeline.thumbnail(item.id, size: .preview) { image = preview }
    }
}

/// Authenticated range playback. Sound settings persist across assets and app launches.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    let headers: [String: String]
    var showsControls = true
    var playing = true
    var onFinished: (@MainActor @Sendable () -> Void)?
    var onProgress: (@MainActor @Sendable () -> Void)?
    var onFailed: (@MainActor @Sendable () -> Void)?
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
        context.coordinator.onFailed = onFailed
        context.coordinator.observe(player, item: item)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFinished = onFinished
        coordinator.onProgress = onProgress
        coordinator.onFailed = onFailed
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
        var onProgress: (@MainActor @Sendable () -> Void)?
        var onFailed: (@MainActor @Sendable () -> Void)?
        private weak var player: AVPlayer?
        private var progressToken: Any?
        private var lastTime = CMTime.zero
        var loop = false
        var playing: Bool?
        var speed = 0.0
        private var token: NSObjectProtocol?
        private var observations: [NSKeyValueObservation] = []

        func observe(_ player: AVPlayer, item: AVPlayerItem) {
            self.player = player
            progressToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, time != self.lastTime else { return }
                    self.lastTime = time
                    self.onProgress?()
                }
            }
            observations = [
                item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    if item.status == .failed {
                        Task { @MainActor [weak self] in self?.onFailed?() }
                    }
                },
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
            if let progressToken { player?.removeTimeObserver(progressToken) }
            progressToken = nil
            player = nil
        }
    }
}
