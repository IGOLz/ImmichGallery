import CoreGraphics
import Foundation

/// Decoder for ThumbHash placeholders (https://evanw.github.io/thumbhash/), which Immich
/// returns for every asset. Port of the reference implementation by Evan Wallace (MIT).
enum ThumbHash {
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImage>() // thread-safe

    static func image(base64: String) -> CGImage? {
        if let cached = cache.object(forKey: base64 as NSString) { return cached }
        guard let data = Data(base64Encoded: base64), let image = decode([UInt8](data)) else { return nil }
        cache.setObject(image, forKey: base64 as NSString)
        return image
    }

    static func decode(_ hash: [UInt8]) -> CGImage? {
        guard hash.count >= 5 else { return nil }
        let header24 = Int(hash[0]) | Int(hash[1]) << 8 | Int(hash[2]) << 16
        let header16 = Int(hash[3]) | Int(hash[4]) << 8
        let lDC = Double(header24 & 63) / 63
        let pDC = Double((header24 >> 6) & 63) / 31.5 - 1
        let qDC = Double((header24 >> 12) & 63) / 31.5 - 1
        let lScale = Double((header24 >> 18) & 31) / 31
        let hasAlpha = (header24 >> 23) != 0
        let pScale = Double((header16 >> 3) & 63) / 63
        let qScale = Double((header16 >> 9) & 63) / 63
        let isLandscape = (header16 >> 15) != 0
        let lx = max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7)
        let ly = max(3, isLandscape ? header16 & 7 : (hasAlpha ? 5 : 7))
        let aDC = hasAlpha && hash.count > 5 ? Double(hash[5] & 15) / 15 : 1
        let aScale = hasAlpha && hash.count > 5 ? Double(hash[5] >> 4) / 15 : 0

        let acStart = hasAlpha ? 6 : 5
        var acIndex = 0
        func decodeChannel(_ nx: Int, _ ny: Int, _ scale: Double) -> [Double] {
            var ac: [Double] = []
            for cy in 0..<ny {
                var cx = cy > 0 ? 0 : 1
                while cx * ny < nx * (ny - cy) {
                    let byteIndex = acStart + (acIndex >> 1)
                    let byte = byteIndex < hash.count ? Int(hash[byteIndex]) : 0
                    ac.append((Double((byte >> ((acIndex & 1) << 2)) & 15) / 7.5 - 1) * scale)
                    acIndex += 1
                    cx += 1
                }
            }
            return ac
        }
        let lAC = decodeChannel(lx, ly, lScale)
        let pAC = decodeChannel(3, 3, pScale * 1.25)
        let qAC = decodeChannel(3, 3, qScale * 1.25)
        let aAC = hasAlpha ? decodeChannel(5, 5, aScale) : []

        let ratio = Double(lx) / Double(ly)
        let w = Int((ratio > 1 ? 32 : 32 * ratio).rounded())
        let h = Int((ratio > 1 ? 32 / ratio : 32).rounded())
        guard w > 0, h > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let nx = max(lx, hasAlpha ? 5 : 3), ny = max(ly, hasAlpha ? 5 : 3)
        var fx = [Double](repeating: 0, count: nx), fy = [Double](repeating: 0, count: ny)
        var i = 0
        for y in 0..<h {
            for cy in 0..<ny { fy[cy] = cos(.pi / Double(h) * (Double(y) + 0.5) * Double(cy)) }
            for x in 0..<w {
                for cx in 0..<nx { fx[cx] = cos(.pi / Double(w) * (Double(x) + 0.5) * Double(cx)) }
                var l = lDC, p = pDC, q = qDC, a = aDC

                var j = 0
                for cy in 0..<ly {
                    var cx = cy > 0 ? 0 : 1
                    let fy2 = fy[cy] * 2
                    while cx * ly < lx * (ly - cy) { l += lAC[j] * fx[cx] * fy2; j += 1; cx += 1 }
                }
                j = 0
                for cy in 0..<3 {
                    var cx = cy > 0 ? 0 : 1
                    let fy2 = fy[cy] * 2
                    while cx < 3 - cy {
                        let f = fx[cx] * fy2
                        p += pAC[j] * f; q += qAC[j] * f
                        j += 1; cx += 1
                    }
                }
                if hasAlpha {
                    j = 0
                    for cy in 0..<5 {
                        var cx = cy > 0 ? 0 : 1
                        let fy2 = fy[cy] * 2
                        while cx < 5 - cy { a += aAC[j] * fx[cx] * fy2; j += 1; cx += 1 }
                    }
                }

                let b = l - 2 / 3 * p
                let r = (3 * l - b + q) / 2
                let g = r - q
                a = max(0, min(1, a))
                rgba[i] = UInt8(max(0, 255 * min(1, r)) * a)
                rgba[i + 1] = UInt8(max(0, 255 * min(1, g)) * a)
                rgba[i + 2] = UInt8(max(0, 255 * min(1, b)) * a)
                rgba[i + 3] = UInt8(255 * a)
                i += 4
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
