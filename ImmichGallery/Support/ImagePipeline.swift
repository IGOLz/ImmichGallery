import CoreGraphics
import Foundation
import ImageIO

/// Loads and decodes Immich media off the main thread with a memory cache in front of the
/// ephemeral URLSession. Cancelling the calling task cancels the network request, which keeps
/// fast scrolling responsive.
final class ImagePipeline: Sendable {
    let client: ImmichClient
    // NSCache is thread-safe.
    nonisolated(unsafe) private let cache: NSCache<NSString, CGImage>

    init(client: ImmichClient) {
        client.session.configuration.urlCache?.removeAllCachedResponses()
        self.client = client.explorePrivateClient() // Explore: media must not survive a move into Locked Folder on disk.
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
        cache.removeAllObjects()
        client.session.configuration.urlCache?.removeAllCachedResponses()
    }

    private func load(_ request: URLRequest, key: String, maxPixelSize: Int?) async -> CGImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let data = try? await client.data(for: request), !Task.isCancelled,
              let image = Self.decode(data, maxPixelSize: maxPixelSize) else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
        return image
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
