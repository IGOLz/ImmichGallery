// Offline check of the production pipeline and placeholder decoder, with an in-memory client.
// swiftc -swift-version 6 ImmichGallery/Support/{ImagePipeline,ThumbHash}.swift Tests/GridImageChecks.swift -o build/check-grid-images && build/check-grid-images
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

actor DownloadBarrier {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        if !opened { await withCheckedContinuation { waiters.append($0) } }
    }
    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

final class ImmichClient: Sendable {
    enum ThumbnailSize: String { case thumbnail, preview, fullsize }
    let session = URLSession(configuration: .ephemeral)
    let data: Data
    let cancelAfterDownload: Bool
    let barrier: DownloadBarrier?
    private let lock = NSLock()
    nonisolated(unsafe) private var requests = 0
    nonisolated(unsafe) private var active = 0
    nonisolated(unsafe) private var peak = 0
    var requestCount: Int { lock.withLock { requests } }
    var peakRequests: Int { lock.withLock { peak } }

    init(data: Data, cancelAfterDownload: Bool = false, barrier: DownloadBarrier? = nil) {
        self.data = data
        self.cancelAfterDownload = cancelAfterDownload
        self.barrier = barrier
    }
    func thumbnailRequest(_ id: String, size: ThumbnailSize, edited: Bool) -> URLRequest {
        URLRequest(url: URL(string: "https://offline.invalid/\(id)/\(size.rawValue)/\(edited)")!)
    }
    func originalRequest(_ id: String, edited: Bool) -> URLRequest {
        thumbnailRequest(id, size: .fullsize, edited: edited)
    }
    func personThumbnailRequest(_ id: String) -> URLRequest {
        thumbnailRequest(id, size: .thumbnail, edited: true)
    }
    func data(for request: URLRequest) async throws -> Data {
        lock.withLock { requests += 1; active += 1; peak = max(peak, active) }
        defer { lock.withLock { active -= 1 } }
        if request.url!.path.contains("/thumbnail/") { await barrier?.wait() }
        try await Task.sleep(for: .milliseconds(5))
        if cancelAfterDownload { withUnsafeCurrentTask { $0?.cancel() } }
        return data
    }
}

@main struct GridImageChecks {
    @MainActor static func main() async {
        let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let client = ImmichClient(data: bytes as Data)
        let pipeline = ImagePipeline(client: client)
        let cancelled = Task { await pipeline.thumbnail("cancelled", size: .thumbnail) }
        cancelled.cancel()
        let cancelledImage = await cancelled.value
        precondition(cancelledImage == nil && client.requestCount == 0, "Cancelled cells must not start requests")

        let image = await pipeline.thumbnail("visible", size: .thumbnail)
        precondition(image?.width == 64 && image?.height == 32)
        _ = await pipeline.thumbnail("visible", size: .thumbnail)
        precondition(client.requestCount == 1, "Returning to a visible cell must reuse its bitmap")
        pipeline.evict(ids: ["visible"])
        precondition(pipeline.cachedThumbnail("visible", size: .thumbnail) == nil)

        let cancellingClient = ImmichClient(data: bytes as Data, cancelAfterDownload: true)
        let cancellingPipeline = ImagePipeline(client: cancellingClient)
        let interrupted = Task { await cancellingPipeline.thumbnail("gone", size: .thumbnail) }
        let interruptedImage = await interrupted.value
        precondition(interruptedImage == nil && cancellingClient.requestCount == 1)
        precondition(cancellingPipeline.cachedThumbnail("gone", size: .thumbnail) == nil)

        let burstClient = ImmichClient(data: bytes as Data)
        let burstPipeline = ImagePipeline(client: burstClient)
        await withTaskGroup(of: Void.self) { group in
            for id in 0..<100 {
                group.addTask { _ = await burstPipeline.gridThumbnail("\(id)", size: .thumbnail) }
            }
        }
        precondition(burstClient.requestCount == 100)
        precondition((2...6).contains(burstClient.peakRequests), "Visible cells must use bounded concurrency")
        let barrier = DownloadBarrier()
        let blockedClient = ImmichClient(data: bytes as Data, barrier: barrier)
        let blockedPipeline = ImagePipeline(client: blockedClient)
        let grid = Task {
            await withTaskGroup(of: Void.self) { group in
                for id in 0..<20 {
                    group.addTask { _ = await blockedPipeline.gridThumbnail("\(id)", size: .thumbnail) }
                }
            }
        }
        while blockedClient.requestCount < 6 { await Task.yield() }
        let viewer = await blockedPipeline.thumbnail("viewer", size: .preview)
        precondition(viewer != nil && blockedClient.requestCount == 7, "Viewer must bypass saturated grid slots")
        await barrier.open()
        await grid.value
        let slots = ThumbnailLoadSlots(limit: 1)
        let acquired = await slots.acquire()
        precondition(acquired)
        let queued = Task { await slots.acquire() }
        await Task.yield()
        queued.cancel()
        let queuedResult = await queued.value
        precondition(!queuedResult, "Cancelled waiters must leave the queue without a free slot")
        await slots.release()
        let reacquired = await slots.acquire()
        precondition(reacquired, "Cancellation must not leak slots")
        await slots.release()

        let hash = Data(repeating: 0, count: 24).base64EncodedString()
        let placeholder = await ThumbHash.placeholder(base64: hash)
        precondition(placeholder != nil)
        let invalid = await ThumbHash.placeholder(base64: "invalid")
        precondition(invalid == nil)
        let cancelledPlaceholder = Task { await ThumbHash.placeholder(base64: hash) }
        cancelledPlaceholder.cancel()
        let result = await cancelledPlaceholder.value
        precondition(result == nil)
        print("Grid image checks passed: cancellation, cache reuse/eviction, async placeholders")
    }
}
