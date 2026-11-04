"""Run the production ImageIO import helper on generated local images only."""
import pathlib
import subprocess
root = pathlib.Path(__file__).resolve().parents[1]
output = root / 'build/AccountImageChecks'
output.mkdir(parents=True, exist_ok=True)
source = (root / 'ImmichGallery/Views/Account/AccountSettingsView.swift').read_text()
helper = source[source.index('nonisolated func accountProfileJPEG'):]
(output / 'ImageHelper.swift').write_text('import Foundation\nimport ImageIO\nimport UniformTypeIdentifiers\n' + helper)
(output / 'Checks.swift').write_text(r'''
import Foundation
import ImageIO
import UniformTypeIdentifiers
@main struct ImageChecks {
    static func main() throws {
        let directory = URL(fileURLWithPath: "build/AccountImageChecks")
        let input = directory.appendingPathComponent("wide.png")
        let invalid = directory.appendingPathComponent("invalid.png")
        let oversized = directory.appendingPathComponent("oversized.png")
        defer { for url in [input, invalid, oversized] { try? FileManager.default.removeItem(at: url) } }
        let context = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8,
            bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 300, y: 0, width: 600, height: 600))
        let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let jpeg = try accountProfileJPEG(url: input)
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(image.width == image.height && image.width <= 512)
        let pixelContext = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        pixelContext.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = pixelContext.data!.assumingMemoryBound(to: UInt8.self)
        precondition(pixel[2] > 240 && pixel[0] < 15, "Expected the blue center crop")
        try Data([1, 2, 3]).write(to: invalid)
        do { _ = try accountProfileJPEG(url: invalid); preconditionFailure() } catch {}
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 51 * 1024 * 1024)
        try handle.close()
        do { _ = try accountProfileJPEG(url: oversized); preconditionFailure() } catch {}
        print("Image checks passed: bounded thumbnail, center square crop, invalid/oversized rejection.")
    }
}
''')
subprocess.run(['swiftc', '-swift-version', '6', 'ImmichGallery/API/Models.swift',
                'ImmichGallery/API/ImmichClient.swift', str(output / 'ImageHelper.swift'),
                str(output / 'Checks.swift'), '-o', str(output / 'check')], cwd=root, check=True)
subprocess.run([str(output / 'check')], cwd=root, check=True)
