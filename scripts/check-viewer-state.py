#!/usr/bin/env python3
"""Run production navigation/close methods with in-memory mocks, never the app."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
source = (repo / 'ImmichGallery/App/ViewerState.swift').read_text()

def method(name, source=source):
    source = source.replace('    private func ', '    func ')
    start = source.index('    func ' + name + '(')
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

harness = r'''
import Foundation
class NSText: NSObject {}
struct TestWindow { var firstResponder: NSObject? }
@MainActor enum NSApp { static var keyWindow: TestWindow? }
enum NSCursor { static func setHiddenUntilMouseMoves(_ hidden: Bool) {} }
struct AssetItem { let id: String; var isVideo = false }
enum PressKey { case leftArrow, rightArrow, space, escape, `return`, delete, deleteForward }
struct PressModifiers: OptionSet {
    let rawValue: Int
    static let command = PressModifiers(rawValue: 1)
}
struct KeyPress {
    enum Result: Equatable { case handled, ignored }
    let key: PressKey
    var modifiers: PressModifiers = []
    var characters = ""
}
@MainActor final class AssetGridModel {
    var viewerID: String? = "a"
    var selection: Set<String> = ["a"]
    var ids = ["a", "b", "c"]
    var delay = false
    func toggleFavorite(_ ids: [String]) async {}
    func item(_ id: String) -> AssetItem? { ids.contains(id) ? AssetItem(id: id) : nil }
    func neighbor(of id: String, delta: Int) async -> AssetItem? {
        if delay { try? await Task.sleep(for: .milliseconds(20)) }
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return nil }
        return item(ids[index + delta])
    }
}
@MainActor final class ViewerCommandContext {
    static let shared = ViewerCommandContext()
    var presentation: ViewerState?
}
@MainActor final class ViewerState {
    func close() { windowWillClose(Notification(name: Notification.Name("close"))) }
    let model = AssetGridModel()
    var sequence: [String] = []
    var sequenceIndex: [String: Int] = [:]
    var navigating = false
    var pendingStep = 0
    var playbackGeneration = 0
    var elapsed = 5.0
    var videoStalledElapsed = 5.0
    var rotation = 90
    var paused = false
    var window: NSObject? = NSObject()
    var slideshow = true
    var settingsPresented = true
    var controlsVisible = false
'''
harness += '\n'.join(method(name) for name in ['neighbor', 'stepWithoutWrapping', 'step', 'windowWillClose'])
harness += r'''
}
@MainActor final class ViewerKeyHarness {
    var viewer: ViewerState?
    var isPresentation = true
    let model: AssetGridModel
    let item = AssetItem(id: "a")
    var onDelete: ([String]) -> Void = { _ in }
    init(_ state: ViewerState) { viewer = state; model = state.model }
    func step(_ delta: Int) { viewer?.step(delta) }
'''
harness += method('handleKey', (repo / 'ImmichGallery/Views/Viewer/AssetViewer.swift').read_text()).replace('private func', 'func')
harness += r'''
}
@main struct Check {
    @MainActor static func main() async {
        let keyboardState = ViewerState()
        keyboardState.slideshow = false
        let keys = ViewerKeyHarness(keyboardState)
        assert(keys.handleKey(KeyPress(key: .space)) == .handled)
        assert(keys.handleKey(KeyPress(key: .return)) == .handled)
        assert(keyboardState.model.viewerID == "a" && !keyboardState.paused, "Space/Return must preserve non-slideshow viewer")
        keyboardState.slideshow = true
        _ = keys.handleKey(KeyPress(key: .space))
        assert(keyboardState.paused && keyboardState.model.viewerID == "a")
        _ = keys.handleKey(KeyPress(key: .escape))
        assert(keyboardState.model.viewerID == nil)
        keyboardState.model.viewerID = "a"
        NSApp.keyWindow = TestWindow(firstResponder: NSText())
        assert(keys.handleKey(KeyPress(key: .rightArrow)) == .ignored)
        assert(keys.handleKey(KeyPress(key: .space)) == .ignored)
        assert(keys.handleKey(KeyPress(key: .return, characters: ".")) == .ignored)
        assert(keyboardState.model.viewerID == "a", "Editing photo details must not navigate or close the viewer")
        NSApp.keyWindow = nil

        let state = ViewerState()
        state.sequence = ["a", "c", "b"]
        state.sequenceIndex = Dictionary(uniqueKeysWithValues: state.sequence.enumerated().map { ($0.element, $0.offset) })
        let next = await state.neighbor(of: "a", delta: 1)
        let previous = await state.neighbor(of: "a", delta: -1)
        assert(next?.id == "c" && previous?.id == "b", "Use slideshow sequence, including backward wrap")
        state.step(1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.model.viewerID == "c" && state.model.selection == ["c"])
        assert(state.elapsed == 0 && state.videoStalledElapsed == 0 && state.rotation == 0)

        state.stepWithoutWrapping(1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.model.viewerID == "b", "Swipes move forward through the sequence")
        state.stepWithoutWrapping(1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.model.viewerID == "b", "Swipes stop at the end of a repeating sequence")
        state.model.viewerID = "a"
        state.stepWithoutWrapping(-1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.model.viewerID == "a", "Swipes stop at the start of a repeating sequence")
        state.model.viewerID = "c"

        state.sequence = ["c"]
        state.sequenceIndex = ["c": 0]
        let generation = state.playbackGeneration
        state.step(1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.model.viewerID == "c" && state.playbackGeneration == generation + 1, "Restart same-item video")

        state.sequence = []
        state.sequenceIndex = [:]
        state.model.viewerID = "a"
        state.model.delay = true
        state.step(1)
        try? await Task.sleep(for: .milliseconds(5))
        state.step(1)
        try? await Task.sleep(for: .milliseconds(100))
        assert(state.model.viewerID == "c", "Navigation arriving during loading must be coalesced")
        state.step(1)
        try? await Task.sleep(for: .milliseconds(50))
        assert(state.paused, "Ordered collection pauses at boundary")

        ViewerCommandContext.shared.presentation = state
        state.windowWillClose(Notification(name: Notification.Name("close")))
        assert(state.model.viewerID == nil && state.model.selection == ["c"])
        assert(!state.slideshow && !state.settingsPresented && state.controlsVisible && state.window == nil)
        assert(ViewerCommandContext.shared.presentation == nil)

        let closing = ViewerState()
        closing.model.delay = true
        closing.step(1)
        try? await Task.sleep(for: .milliseconds(5))
        closing.windowWillClose(Notification(name: Notification.Name("close")))
        try? await Task.sleep(for: .milliseconds(50))
        assert(closing.model.viewerID == nil, "An in-flight navigation must not reopen the inline viewer")
        print("Viewer state checks passed: keyboard, sequence, wraparound, swipe boundaries, coalescing, restart, boundary and close")
    }
}
'''
(repo / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='viewer-state-check-', dir=repo / 'build') as directory:
    swift = Path(directory) / 'Checks.swift'
    executable = Path(directory) / 'checks'
    swift.write_text(harness)
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
