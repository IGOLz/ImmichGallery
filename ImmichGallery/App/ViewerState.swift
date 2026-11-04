import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ViewerState: NSObject, NSWindowDelegate {
    let model: AssetGridModel
    let session: LibrarySession
    var rotation = 0
    var slideshow = false
    var paused = false
    var settingsPresented = false
    var window: NSWindow?
    var preparing = false
    var elapsed = 0.0
    var sequence: [String] = []
    private var selectionSequence: [String] = []
    private var navigating = false
    var controlsVisible = true
    var interval: Double = UserDefaults.standard.object(forKey: "viewer.interval") as? Double ?? 5 {
        didSet { UserDefaults.standard.set(interval, forKey: "viewer.interval") }
    }
    var shuffle = UserDefaults.standard.bool(forKey: "viewer.shuffle") {
        didSet { UserDefaults.standard.set(shuffle, forKey: "viewer.shuffle"); Task { await rebuildSequence() } }
    }
    var fade = UserDefaults.standard.object(forKey: "viewer.fade") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fade, forKey: "viewer.fade") }
    }
    var limitVideos = UserDefaults.standard.bool(forKey: "viewer.limitVideos") {
        didSet { UserDefaults.standard.set(limitVideos, forKey: "viewer.limitVideos") }
    }

    init(model: AssetGridModel, session: LibrarySession) {
        self.model = model
        self.session = session
    }

    var currentID: String? { model.viewerID ?? (model.selection.count == 1 ? model.selection.first : nil) }

    func present(slideshow: Bool) {
        guard !preparing else { return }
        preparing = true
        Task {
            defer { preparing = false }
            await model.loadIfNeeded()
            if model.viewerID == nil {
                if model.sections.first?.assets == nil { await model.viewerLoadSection(0) }
                model.viewerID = model.sections.flatMap { $0.assets ?? [] }.first { model.selection.contains($0.id) }?.id ?? model.sections.first?.assets?.first?.id
            }
            guard model.viewerID != nil else { return }
            self.slideshow = slideshow
            paused = false
            elapsed = 0
            selectionSequence = model.selection.count > 1
                ? model.sections.flatMap { $0.assets ?? [] }.filter { model.selection.contains($0.id) }.map(\.id) : []
            await rebuildSequence()
            if let id = model.viewerID { model.selection = [id] }
            guard window == nil else { return }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Viewer"
            window.collectionBehavior = [.fullScreenPrimary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ViewerPresentation(state: self).environment(session).environment(self))
            self.window = window
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }
    }

    private func rebuildSequence() async {
        guard slideshow else { sequence = []; return }
        do {
            sequence = selectionSequence
            if shuffle {
                if sequence.isEmpty { sequence = try await model.viewerAllItems().map(\.id) }
                sequence.shuffle()
            }
        } catch { model.lastError = error.localizedDescription; session.handle(error) }
    }

    func step(_ delta: Int) {
        guard !navigating else { return }
        navigating = true
        Task {
            defer { navigating = false }
            guard let id = model.viewerID else { return }
            let next: String?
            if !sequence.isEmpty, let index = sequence.firstIndex(of: id) {
                next = sequence[(index + delta + sequence.count) % sequence.count]
            } else {
                next = await model.neighbor(of: id, delta: delta)?.id
            }
            guard let next else { paused = true; return }
            model.viewerID = next
            model.selection = [next]
            elapsed = 0
            rotation = 0
        }
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        window = nil
        slideshow = false
        settingsPresented = false
        controlsVisible = true
        sequence = []
    }
    func windowDidExitFullScreen(_ notification: Notification) { close() }

    func copy(original: Bool = false, asFile: Bool = false) {
        guard let id = currentID else { return }
        Task {
            do {
                if asFile {
                    let asset = try await session.client.asset(id)
                    let (temporaryFile, response) = try await session.client.session.download(for: session.client.originalRequest(id))
                    defer { try? FileManager.default.removeItem(at: temporaryFile) }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ViewerClipboard/\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent((asset.originalFileName as NSString).lastPathComponent)
                    try FileManager.default.copyItem(at: temporaryFile, to: file)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([file as NSURL])
                } else {
                    let image: NSImage
                    if original {
                        let data = try await session.client.data(for: session.client.originalRequest(id))
                        guard let decoded = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                        image = decoded
                    } else {
                        guard let preview = await session.pipeline.thumbnail(id, size: .preview) else { throw CocoaError(.fileReadCorruptFile) }
                        image = NSImage(cgImage: preview, size: .zero)
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            } catch { model.lastError = error.localizedDescription; session.handle(error) }
        }
    }

    func showInLibrary() {
        guard let id = currentID else { return }
        Task {
            do {
                let asset = try await session.client.asset(id)
                let library = session.gridModel(for: .library)
                await library.loadIfNeeded()
                if let index = library.sections.firstIndex(where: { $0.id.prefix(7) == asset.localDateTime.prefix(7) }) {
                    await library.viewerLoadSection(index)
                }
                guard library.item(id) != nil else {
                    model.lastError = "This item isn't in All Photos. It may be archived, hidden, trashed, or part of a stack."
                    return
                }
                close()
                library.viewerID = nil
                library.selection = [id]
                library.viewerScrollTarget = id
                NotificationCenter.default.post(name: .viewerShowLibrary, object: nil)
            } catch { model.lastError = error.localizedDescription; session.handle(error) }
        }
    }
}

extension Notification.Name {
    static let viewerShowLibrary = Notification.Name("viewerShowLibrary")
}
