import AppKit
import Quartz

@MainActor
final class MacQuickLook: NSResponder, @preconcurrency QLPreviewPanelDataSource {
    static let shared = MacQuickLook()
    private weak var sourceWindow: NSWindow?
    private var files: [URL] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func toggle(_ ids: [String], session: LibrarySession, onError: @escaping (String) -> Void) {
        if task != nil || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible) {
            dismiss()
            return
        }
        sourceWindow = NSApp.keyWindow
        let current = UUID()
        generation = current
        task = Task {
            defer { if generation == current { task = nil } }
            do {
                // shortcut: preview at most 20 originals; use the viewer/exporter for larger selections.
                for id in ids.prefix(20) {
                    let url = try await session.client.macIntegrationOriginal(id, preview: true)
                    guard !Task.isCancelled, generation == current else {
                        MacTransferCache.release(url.deletingLastPathComponent(), remove: true)
                        return
                    }
                    files.append(url)
                    let panel = QLPreviewPanel.shared()!
                    if files.count == 1 {
                        nextResponder = sourceWindow?.nextResponder
                        sourceWindow?.nextResponder = self
                        panel.makeKeyAndOrderFront(nil)
                        panel.currentPreviewItemIndex = 0
                    }
                    panel.reloadData()
                }
            } catch {
                if generation == current, !error.isCancellation { session.handle(error); onError(error.localizedDescription) }
            }
        }
    }

    func dismiss() {
        generation = UUID()
        task?.cancel()
        task = nil
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().orderOut(nil) }
        cleanUp()
    }

    private func cleanUp() {
        if let sourceWindow, sourceWindow.nextResponder === self { sourceWindow.nextResponder = nextResponder }
        sourceWindow = nil
        nextResponder = nil
        files.forEach { MacTransferCache.release($0.deletingLastPathComponent(), remove: true) }
        files = []
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = self }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            generation = UUID()
            task?.cancel()
            task = nil
            cleanUp()
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { files.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        files.indices.contains(index) ? files[index] as NSURL : nil
    }
}
