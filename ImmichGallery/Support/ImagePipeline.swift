import CoreGraphics
import Foundation
import ImageIO

/// Loads and decodes Immich media off the main thread with a memory cache in front of the
/// cached URLSession. Cancelling the calling task cancels the network request, which keeps
/// fast scrolling responsive.
final class ImagePipeline: Sendable {
    let client: ImmichClient
    // NSCache is thread-safe.
    nonisolated(unsafe) private let cache: NSCache<NSString, CGImage>

    private let evictionLock = NSLock()
    nonisolated(unsafe) private var revisions: [String: Int] = [:]
    nonisolated(unsafe) private var revision = 0

    init(client: ImmichClient) {
        self.client = client
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 512 << 20
        self.cache = cache
    }

    func cachedThumbnail(_ id: String, size: ImmichClient.ThumbnailSize) -> CGImage? {
        cache.object(forKey: "\(id)-\(size.rawValue)" as NSString)
    }

    func thumbnail(_ id: String, size: ImmichClient.ThumbnailSize) async -> CGImage? {
        await load(client.thumbnailRequest(id, size: size), key: "\(id)-\(size.rawValue)", maxPixelSize: nil)
    }

    func personThumbnail(_ id: String) async -> CGImage? {
        await load(client.personThumbnailRequest(id), key: "person-\(id)", maxPixelSize: nil)
    }

    /// Full-resolution original (HEIC, RAW, JPEG…), downsampled to `maxPixelSize`.
    func original(_ id: String, maxPixelSize: Int = 8192) async -> CGImage? {
        await load(client.originalRequest(id), key: "\(id)-original", maxPixelSize: maxPixelSize)
    }

    func removeAll() {
        evictionLock.withLock {
            revision += 1
            cache.removeAllObjects()
            client.session.configuration.urlCache?.removeAllCachedResponses()
        }
    }

    func evict(ids: [String]) {
        evictionLock.withLock {
            for id in ids {
                for size in [ImmichClient.ThumbnailSize.thumbnail, .preview, .fullsize] {
                    evict(key: "\(id)-\(size.rawValue)", request: client.thumbnailRequest(id, size: size))
                }
                evict(key: "\(id)-original", request: client.originalRequest(id))
            }
        }
    }

    private func evict(key: String, request: URLRequest) {
        revisions[key, default: 0] += 1
        cache.removeObject(forKey: key as NSString)
        client.session.configuration.urlCache?.removeCachedResponse(for: request)
    }

    private func load(_ request: URLRequest, key: String, maxPixelSize: Int?) async -> CGImage? {
        let started = evictionLock.withLock { (revision, revisions[key, default: 0]) }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let data = try? await client.data(for: request)
        let image = data.flatMap { Self.decode($0, maxPixelSize: maxPixelSize) }
        return evictionLock.withLock {
            // A request started before eviction may finish after the delayed purge.
            guard started == (revision, revisions[key, default: 0]) else {
                client.session.configuration.urlCache?.removeCachedResponse(for: request)
                return nil
            }
            guard !Task.isCancelled, let image else { return nil }
            cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
            return image
        }
    }

    static func decode(_ data: Data, maxPixelSize: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        else if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(w, h)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
