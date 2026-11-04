import SwiftUI

extension FocusedValues {
    @Entry var viewerState: ViewerState?
}

struct ViewerIntegration: ViewModifier {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel
    @State private var state: ViewerState?

    func body(content: Content) -> some View {
        Group {
            if let state {
                content.environment(state)
                    .focusedSceneValue(\.viewerState, state)
                    .toolbar {
                        ToolbarItem {
                            Button { state.present(slideshow: true) } label: { Label("Slideshow", systemImage: "play.rectangle") }
                                .disabled(model.totalCount == 0 || state.preparing)
                        }
                        ToolbarItem {
                            if model.viewerID != nil {
                                Button { state.present(slideshow: false) } label: { Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                            }
                        }
                    }
                    .onChange(of: model.viewerID) { state.rotation = 0; state.elapsed = 0 }
                    .onDisappear { state.close() }
            } else { ProgressView().task { state = ViewerState(model: model, session: session) } }
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.viewerState) private var state

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Copy Image") { state?.copy() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(state?.currentID == nil || state?.model.item(state?.currentID ?? "")?.isVideo == true)
            Button("Copy Original Image") { state?.copy(original: true) }
                .disabled(state?.currentID == nil || state?.model.item(state?.currentID ?? "")?.isVideo == true)
            Button("Copy as File") { state?.copy(asFile: true) }.disabled(state?.currentID == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Start Slideshow") { state?.present(slideshow: true) }.disabled(state == nil || state?.model.totalCount == 0)
            Button("Open Full-Screen Viewer") { state?.present(slideshow: false) }.disabled(state?.currentID == nil)
            Button("Rotate View Left") { state?.rotation -= 90 }.disabled(state?.model.viewerID == nil)
            Button("Rotate View Right") { state?.rotation += 90 }.disabled(state?.model.viewerID == nil)
            Button("Show in All Photos") { state?.showInLibrary() }.disabled(state?.currentID == nil)
        }
    }
}

struct ViewerContextMenu: View {
    @Environment(LibrarySession.self) private var session
    let model: AssetGridModel
    let asset: AssetItem
    var body: some View {
        Button("Show in All Photos") {
            let state = ViewerState(model: model, session: session)
            model.selection = [asset.id]
            state.showInLibrary()
        }
    }
}

struct ViewerPresentation: View {
    @Bindable var state: ViewerState
    @State private var live = false
    @State private var lastInteraction = Date()
    @State private var overControls = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            if let id = state.model.viewerID, let item = state.model.item(id) {
                AssetViewer(model: state.model, item: item, playLive: $live, onDelete: { _ in }, isPresentation: true)
                    .id(id)
                    .transition(state.fade ? .opacity : .identity)
            }
            if state.controlsVisible {
                HStack(spacing: 20) {
                    Button { state.close() } label: { Label("Exit Full Screen", systemImage: "xmark") }
                    Button { state.step(-1) } label: { Label("Previous", systemImage: "backward.end.fill") }
                    if state.slideshow {
                        Button { state.paused.toggle() } label: { Label(state.paused ? "Play" : "Pause", systemImage: state.paused ? "play.fill" : "pause.fill") }
                    }
                    Button { state.step(1) } label: { Label("Next", systemImage: "forward.end.fill") }
                    Button { state.showInLibrary() } label: { Label("Show in All Photos", systemImage: "square.grid.2x2") }
                    Button { state.settingsPresented.toggle() } label: { Label("Slideshow Settings", systemImage: "gearshape") }
                        .popover(isPresented: $state.settingsPresented) { ViewerSlideshowSettings(state: state) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(20)
                .glassEffect(.regular, in: .capsule)
                .padding(24)
                .onHover { overControls = $0 }
            }
        }
        .animation(state.fade ? .easeInOut(duration: 0.35) : nil, value: state.model.viewerID)
        .focusedSceneValue(\.viewerState, state)
        .alert("Something Went Wrong", isPresented: Binding(get: { state.model.lastError != nil }, set: { if !$0 { state.model.lastError = nil } })) {
            Button("OK") {}
        } message: { Text(state.model.lastError ?? "") }
        .onContinuousHover { _ in state.controlsVisible = true; lastInteraction = .now }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                if Date().timeIntervalSince(lastInteraction) > 2.5 && !overControls && !state.settingsPresented { state.controlsVisible = false }
                guard state.slideshow, !state.paused, !state.settingsPresented else { continue }
                let isVideo = state.model.viewerID.flatMap(state.model.item)?.isVideo == true
                guard !isVideo || state.limitVideos else { continue }
                state.elapsed += 0.25
                if state.elapsed >= state.interval { state.elapsed = 0; state.step(1) }
            }
        }
    }
}

struct ViewerSlideshowSettings: View {
    @Bindable var state: ViewerState
    var body: some View {
        Form {
            Text("Slideshow Settings").font(.headline)
            Picker("Interval", selection: $state.interval) {
                ForEach([2.0, 3, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
            }
            Toggle("Shuffle", isOn: $state.shuffle)
            Toggle("Fade Transition", isOn: $state.fade)
            Toggle("Limit Videos to Slide Interval", isOn: $state.limitVideos)
            Text("Videos otherwise play to the end. Space pauses or resumes playback.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 320)
    }
}
