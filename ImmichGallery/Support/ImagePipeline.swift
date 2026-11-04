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

    func cachedThumbnail(_ id: String, size: ImmichClient.ThumbnailSize, edited: Bool = true) -> CGImage? {
        cache.object(forKey: "\(id)-\(size.rawValue)-\(edited)" as NSString)
    }

    func thumbnail(_ id: String, size: ImmichClient.ThumbnailSize, edited: Bool = true) async -> CGImage? {
        await load(client.thumbnailRequest(id, size: size, edited: edited), key: "\(id)-\(size.rawValue)-\(edited)", maxPixelSize: nil)
    }

    func personThumbnail(_ id: String) async -> CGImage? {
        await load(client.personThumbnailRequest(id), key: "person-\(id)", maxPixelSize: nil)
    }

    func invalidatePerson(_ id: String) {
        cache.removeObject(forKey: "person-\(id)" as NSString)
        client.session.configuration.urlCache?.removeCachedResponse(for: client.personThumbnailRequest(id))
    }

    /// Featured thumbnails are generated asynchronously by the server.
    func refreshPersonThumbnail(_ id: String, replacing previous: Data?) async {
        invalidatePerson(id)
        for delay in [1, 3, 6] {
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            invalidatePerson(id)
            var request = client.personThumbnailRequest(id)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let data = try? await client.data(for: request), !Task.isCancelled else { continue }
            guard data != previous, let image = Self.decode(data, maxPixelSize: nil) else { continue }
            cache.setObject(image, forKey: "person-\(id)" as NSString, cost: image.bytesPerRow * image.height)
            return
        }
        // Don't leave an old cached response behind after retries expire.
        invalidatePerson(id)
    }

    /// Full-resolution original (HEIC, RAW, JPEG…), downsampled to `maxPixelSize`.
    func original(_ id: String, maxPixelSize: Int = 8192, edited: Bool = false) async -> CGImage? {
        await load(client.originalRequest(id, edited: edited), key: "\(id)-original-\(edited)", maxPixelSize: maxPixelSize)
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
            // Metadata adds edited/unedited variants, so evict both.
            for id in ids {
                for edited in [true, false] {
                    for size in [ImmichClient.ThumbnailSize.thumbnail, .preview, .fullsize] {
                        evict(key: "\(id)-\(size.rawValue)-\(edited)", request: client.thumbnailRequest(id, size: size, edited: edited))
                    }
                    evict(key: "\(id)-original-\(edited)", request: client.originalRequest(id, edited: edited))
                }
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
