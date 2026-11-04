import AVKit
import SwiftUI

/// Single-asset viewer shown in place of the grid (like double-clicking in Photos).
struct AssetViewer: View {
    @Environment(LibrarySession.self) private var session
    @Bindable var model: AssetGridModel
    let item: AssetItem
    @Binding var playLive: Bool
    let onDelete: ([String]) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            if item.isVideo {
                VideoPlayerView(url: session.client.videoURL(item.id), headers: session.client.credential?.headers ?? [:])
                    .id(item.id)
                    .draggable(OriginalTransfer(id: item.id, isVideo: true, client: session.client))
            } else {
                ZoomableImage(item: item)
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

            HStack {
                navButton("chevron.left", delta: -1)
                Spacer()
                navButton("chevron.right", delta: 1)
            }
            .padding(.horizontal, 16)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(action: handleKey)
        .onExitCommand { model.viewerID = nil }
        .task(id: item.id) { await prefetchNeighbours() }
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
        Task {
            if let next = await model.neighbor(of: item.id, delta: delta) {
                model.viewerID = next.id
                model.selection = [next.id]
            }
        }
    }

    private func prefetchNeighbours() async {
        for delta in [1, -1] {
            if let next = await model.neighbor(of: item.id, delta: delta), !next.isVideo {
                _ = await session.pipeline.thumbnail(next.id, size: .preview)
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
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

    @State private var image: CGImage?
    @State private var hasOriginal = false
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geo in
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
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * gestureScale)
            .offset(offset)
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
                Task { if let original = await session.pipeline.original(item.id) { image = original } }
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

/// AVPlayerView wrapper. Immich needs auth headers on media requests, which AVURLAsset supports
/// via `AVURLAssetHTTPHeaderFieldsKey`; range requests are supported by `/video/playback`.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    let headers: [String: String]
    var showsControls = true
    var onFinished: (@MainActor @Sendable () -> Void)?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .floating : .none
        view.allowsPictureInPicturePlayback = showsControls
        view.showsFullScreenToggleButton = showsControls
        view.videoGravity = .resizeAspect

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        view.player = player
        context.coordinator.observe(item, onFinished: onFinished)
        player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?

        func observe(_ item: AVPlayerItem, onFinished: (@MainActor @Sendable () -> Void)?) {
            guard let onFinished else { return }
            token = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { _ in
                MainActor.assumeIsolated { onFinished() }
            }
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
