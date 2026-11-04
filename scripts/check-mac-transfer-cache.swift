// Offline cache check using only an isolated, disposable directory.
// swiftc -parse-as-library ImmichGallery/API/{Models,ImmichClient,ImmichClient+MacIntegration}.swift \
//   scripts/check-mac-transfer-cache.swift -o build/check-mac-transfer-cache
import Foundation

@main struct CheckMacTransferCache {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-cache-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let preview = try MacTransferCache.create(preview: true, root: root)
        let drag = try MacTransferCache.create(preview: false, root: root)
        let original = drag.appendingPathComponent("original.heic")
        try Data([1, 2, 3]).write(to: original)
        MacTransferCache.release(drag, remove: false)
        MacTransferCache.prune(root: root)
        assert(fm.fileExists(atPath: original.path), "Fresh promise must survive")
        MacTransferCache.prune(root: root, now: Date().addingTimeInterval(601))
        assert(!fm.fileExists(atPath: drag.path), "Expired drag must be removed")
        assert(fm.fileExists(atPath: preview.path), "Leased Quick Look folder must survive")
        MacTransferCache.release(preview, remove: true)
        assert(!fm.fileExists(atPath: preview.path))
        let legacy = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        MacTransferCache.prune(root: root, now: Date().addingTimeInterval(601))
        assert(!fm.fileExists(atPath: legacy.path), "Legacy cache must expire too")
        print("Passed: fresh promises, expired promises, leased previews, release, legacy cleanup")
    }
}
