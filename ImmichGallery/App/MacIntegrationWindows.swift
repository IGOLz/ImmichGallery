import SwiftUI

struct MacWindowRoute: Codable, Hashable {
    var instance = UUID()
    var albumID: String?
    var query: String?
}

struct MacWindowRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let route: MacWindowRoute?
    @State private var session: LibrarySession?

    var body: some View {
        Group {
            if let session {
                MainView(initialAlbumID: route?.albumID, initialSearch: route?.query)
                    .environment(session)
            } else {
                RootView()
            }
        }
        .task(id: app.session.map(ObjectIdentifier.init)) {
            if let shared = app.session {
                let independent = LibrarySession(client: shared.client, user: shared.user)
                independent.onUnauthorized = shared.onUnauthorized
                session = independent
                await independent.bootstrap()
            } else { session = nil; MacQuickLook.shared.dismiss() }
            openPendingIntent()
        }
        .onChange(of: MacIntegrationRouter.shared.pending) { openPendingIntent() }
    }

    private func openPendingIntent() {
        guard app.session != nil, let pending = MacIntegrationRouter.shared.pending else { return }
        MacIntegrationRouter.shared.pending = nil
        openWindow(id: "main", value: pending)
    }
}

struct MacAlbumWindowMenu: View {
    @Environment(\.openWindow) private var openWindow
    let albumID: String

    var body: some View {
        Button("Open Album in New Window") { openWindow(id: "main", value: MacWindowRoute(albumID: albumID)) }
        Button("Open in New Tab") {
            let source = NSApp.keyWindow
            let previous = Set(NSApp.windows.map(\.windowNumber))
            openWindow(id: "main", value: MacWindowRoute(albumID: albumID))
            Task { @MainActor in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(50))
                    if let window = NSApp.windows.first(where: { !previous.contains($0.windowNumber) && $0.isVisible }) {
                        source?.addTabbedWindow(window, ordered: .above)
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }
        }
    }
}

struct MacIntegrationCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main", value: MacWindowRoute()) }
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}
