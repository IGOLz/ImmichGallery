import SwiftUI

struct ExploreMemoryScene: Scene {
    let app: AppModel
    var body: some Scene {
        WindowGroup("Memories", id: "explore-memory", for: String.self) { $id in
            if let session = app.session, let id {
                ExploreMemoryWindow(id: id).environment(session)
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct ExploreMemoryWindow: View {
    @Environment(LibrarySession.self) private var session
    let id: String
    @State private var memory: ExploreMemory?
    @State private var duration = 5
    @State private var error: String?
    var body: some View {
        Group {
            if let memory { ExploreMemoryPlayer(memory: memory, duration: duration) }
            else if let error { ContentUnavailableView("Memory Unavailable", systemImage: "photo", description: Text(error)) }
            else { ProgressView() }
        }
        .frame(minWidth: 760, minHeight: 480)
        .task(id: id) {
            do {
                let preferences = try await session.client.explorePreferences()
                guard preferences.memories?.enabled == true else { error = "Memories are disabled in Immich Account Settings."; return }
                duration = max(1, preferences.memories?.duration ?? 5)
                var loaded: ExploreMemory = try await session.client.get("memories/\(id)")
                loaded.assets.removeAll { $0.visibility == "locked" }
                memory = loaded
            } catch { self.error = error.localizedDescription }
        }
    }
}
