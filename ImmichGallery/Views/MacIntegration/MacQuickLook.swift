import AppKit
import Quartz

@MainActor
final class MacQuickLook: NSResponder, @preconcurrency QLPreviewPanelDataSource {
    static let shared = MacQuickLook()
    private weak var sourceWindow: NSWindow?
    private var files: [URL] = []
    private var task: Task<Void, Never>?

    func toggle(_ ids: [String], session: LibrarySession, onError: @escaping (String) -> Void) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            task?.cancel()
            return
        }
        task?.cancel()
        task = Task {
            var downloaded: [URL] = []
            do {
                for id in ids {
                    let url = try await session.client.macIntegrationOriginal(id)
                    downloaded.append(url)
                    try Task.checkCancellation()
                }
                guard !downloaded.isEmpty else { return }
                files.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
                files = downloaded
                if let sourceWindow, sourceWindow.nextResponder === self { sourceWindow.nextResponder = nextResponder }
                sourceWindow = NSApp.keyWindow
                nextResponder = sourceWindow?.nextResponder
                sourceWindow?.nextResponder = self
                let panel = QLPreviewPanel.shared()!
                panel.makeKeyAndOrderFront(nil)
                panel.reloadData()
                panel.currentPreviewItemIndex = 0
            } catch {
                downloaded.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
                if !error.isCancellation { session.handle(error); onError(error.localizedDescription) }
            }
        }
    }

    func dismiss() {
        task?.cancel()
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().orderOut(nil) }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = self }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            if let sourceWindow, sourceWindow.nextResponder === self { sourceWindow.nextResponder = nextResponder }
            sourceWindow = nil
            nextResponder = nil
            files.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
            files = []
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { files.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        files[index] as NSURL
    }
}
