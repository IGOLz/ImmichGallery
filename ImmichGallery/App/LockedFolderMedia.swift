import AppKit
import Foundation

/// Media for one unlock of the Locked Folder: a connection without a URL cache, a memory-only image
/// cache and its own temporary files. `discard()` removes all of it when the folder locks.
@MainActor
final class LockedFolderMedia {
    let client: ImmichClient
    let pipeline: ImagePipeline
    private(set) var isDiscarded = false
    /// A failed request may mean the unlock expired; the Locked Folder view checks and locks.
    var onRequestFailed: () -> Void = {}
    /// The pasteboard change made by copying a locked item. Cleared on lock if nothing replaced it.
    var pasteboardChangeCount: Int?

    init(account: ImmichClient) {
        client = account.explorePrivateClient(transferRoot: MacTransferCache.lockedRoot.appendingPathComponent(UUID().uuidString, isDirectory: true))
        pipeline = ImagePipeline(client: client)
    }

    func requestFailed() { if !isDiscarded { onRequestFailed() } }

    func discard() {
        isDiscarded = true
        onRequestFailed = {}
        pipeline.removeAll()
        client.session.invalidateAndCancel()
        if let root = client.transferRoot { MacTransferCache.discard(root: root) }
        if let pasteboardChangeCount, NSPasteboard.general.changeCount == pasteboardChangeCount { NSPasteboard.general.clearContents() }
        pasteboardChangeCount = nil
    }

    /// Files left by a run that quit without locking.
    nonisolated static func sweep() { try? FileManager.default.removeItem(at: MacTransferCache.lockedRoot) }
}

/// An app-side deadline, independent of background requests extending the server unlock.
struct LockedFolderInactivity {
    static let timeout: TimeInterval = 15 * 60
    private(set) var deadline: Date?

    mutating func resignActive(now: Date = .now) { deadline = now.addingTimeInterval(Self.timeout) }
    mutating func becomeActive(now: Date = .now) -> Bool {
        defer { deadline = nil }
        return deadline.map { now >= $0 } ?? false
    }
}
