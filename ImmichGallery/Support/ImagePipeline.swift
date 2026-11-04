import CoreGraphics
import Foundation
import ImageIO

/// Loads and decodes Immich media off the main thread with a memory cache in front of the
/// shared URLCache. Cancelling the calling task cancels the network request, which keeps
/// fast scrolling responsive.
final class ImagePipeline: Sendable {
    let client: ImmichClient
    // NSCache is thread-safe.
    nonisolated(unsafe) private let cache: NSCache<NSString, CGImage>

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

    /// Full-resolution original (HEIC, RAW, JPEG…), downsampled to `maxPixelSize`.
    func original(_ id: String, maxPixelSize: Int = 8192, edited: Bool = false) async -> CGImage? {
        await load(client.originalRequest(id, edited: edited), key: "\(id)-original-\(edited)", maxPixelSize: maxPixelSize)
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
