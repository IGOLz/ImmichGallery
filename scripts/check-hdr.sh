#!/bin/zsh
# Compiles the production ImagePipeline and HDRImage sources against an in-memory client and
# checks HDR decoding and the EDR layer. Never launches the app or contacts a server.
set -euo pipefail
cd "${0:A:h}/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'EOF'
import AppKit
import CoreImage
import ImageIO
import SwiftUI

final class ImmichClient: Sendable {
    enum ThumbnailSize: String, Sendable { case thumbnail, preview, fullsize }
    let session = URLSession(configuration: .ephemeral)
    let originals: [String: Data]
    nonisolated(unsafe) var fetches: [String] = []
    init(originals: [String: Data]) { self.originals = originals }
    private func url(_ path: String) -> URLRequest { URLRequest(url: URL(string: "https://example.invalid/\(path)")!) }
    func thumbnailRequest(_ id: String, size: ThumbnailSize, edited: Bool = true) -> URLRequest { url("t/\(id)") }
    func originalRequest(_ id: String, edited: Bool = false) -> URLRequest { url("o/\(id)") }
    func personThumbnailRequest(_ id: String) -> URLRequest { url("p/\(id)") }
    func data(for request: URLRequest) async throws -> Data {
        let id = request.url!.lastPathComponent
        fetches.append(id)
        guard let data = originals[id] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
    print("ok: \(message)")
}

// A 1200×800 gradient from black to 4× SDR white, saved as HEIC with an ISO gain map.
let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let hdrSource = CIFilter(name: "CILinearGradient", parameters: [
    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 1200, y: 0),
    "inputColor0": CIColor(red: 0, green: 0, blue: 0, colorSpace: linear)!,
    "inputColor1": CIColor(red: 4, green: 4, blue: 4, colorSpace: linear)!,
])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1200, height: 800))
let sdrSource = hdrSource.applyingFilter("CIToneMapHeadroom", parameters: ["inputSourceHeadroom": 4.0, "inputTargetHeadroom": 1.0])
let context = CIContext()
let heic = context.heifRepresentation(of: sdrSource, format: .RGBA8, colorSpace: p3, options: [.hdrImage: hdrSource])!
let jpeg = context.jpegRepresentation(of: sdrSource, colorSpace: p3)!

let client = ImmichClient(originals: ["hdr": heic, "sdr": jpeg])
let pipeline = ImagePipeline(client: client)

let sdrDecode = ImagePipeline.decode(heic, maxPixelSize: 600)!
check(sdrDecode.contentHeadroom <= 1, "default decode stays SDR")

let hdr = await pipeline.hdrOriginal("hdr", maxPixelSize: 600)
check(hdr != nil, "gain-map HEIC decodes to HDR")
check((hdr?.contentHeadroom ?? 0) > 3, "HDR headroom is about 4× (\(hdr?.contentHeadroom ?? 0))")
check(hdr?.width == 600 && hdr?.height == 400, "HDR decode honours maxPixelSize")

check(await pipeline.hdrOriginal("sdr", maxPixelSize: 600) == nil, "SDR JPEG is not shown as HDR")
check(await pipeline.hdrOriginal("sdr", maxPixelSize: 600) == nil, "SDR JPEG is remembered")
check(client.fetches.filter { $0 == "sdr" }.count == 1, "SDR original is downloaded only once")
pipeline.evict(ids: ["sdr"])
_ = await pipeline.hdrOriginal("sdr", maxPixelSize: 600)
check(client.fetches.filter { $0 == "sdr" }.count == 2, "eviction forgets the SDR result")
check(await pipeline.hdrOriginal("missing", maxPixelSize: 600) == nil, "failed download returns nil")
_ = await pipeline.hdrOriginal("missing", maxPixelSize: 600)
check(client.fetches.filter { $0 == "missing" }.count == 2, "failed download is retried later")

check(HDRPhotos.mayContainHDR(mimeType: "image/HEIC") && HDRPhotos.mayContainHDR(mimeType: "image/jpeg")
      && HDRPhotos.mayContainHDR(mimeType: "image/avif"), "HEIC, JPEG and AVIF are candidates")
check(!HDRPhotos.mayContainHDR(mimeType: "image/x-adobe-dng") && !HDRPhotos.mayContainHDR(mimeType: "image/gif")
      && !HDRPhotos.mayContainHDR(mimeType: nil), "RAW, GIF and unknown types are skipped")

await MainActor.run {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: HDRImageLayer(image: hdr!).frame(width: 300, height: 200))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    @MainActor func find(_ view: NSView) -> NSView? { view is HDRImageLayer.LayerView ? view : view.subviews.lazy.compactMap(find).first }
    guard let view = find(host), let layer = view.layer else { check(false, "HDR layer view exists"); return }
    check(layer.contents.map { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID } == true, "layer shows the HDR bitmap")
    check(layer.contentsGravity == .resizeAspect, "layer is aspect-fit like the SDR image")
    if #available(macOS 26, *) {
        check(layer.preferredDynamicRange == .high, "layer prefers high dynamic range")
    } else {
        check(layer.wantsExtendedDynamicRangeContent, "layer wants EDR content")
    }
    check(view.hitTest(NSPoint(x: 10, y: 10)) == nil, "layer passes mouse events through")
}
print("HDR checks passed.")
EOF

swiftc -swift-version 6 -o "$WORK/check" \
  ImmichGallery/Support/ImagePipeline.swift ImmichGallery/Support/HDRImage.swift "$WORK/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$WORK/check" ]] || { echo "Build failed." >&2; exit 1; }
"$WORK/check"
