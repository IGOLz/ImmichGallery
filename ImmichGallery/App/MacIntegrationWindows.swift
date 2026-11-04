import SwiftUI

struct MacWindowRoute: Codable, Hashable {
    var instance = UUID()
    var albumID: String?
    var query: String?
    var asTab: Bool?
}

struct MacWindowRoot: View {
    let app: AppModel
    let route: MacWindowRoute?
    @State private var session: LibrarySession?
    @State private var sharedID: ObjectIdentifier?

    init(app: AppModel, route: MacWindowRoute?) {
        self.app = app
        self.route = route
        _session = State(initialValue: app.session.map(Self.independentSession))
        _sharedID = State(initialValue: app.session.map(ObjectIdentifier.init))
    }

    private static func independentSession(_ shared: LibrarySession) -> LibrarySession {
        let session = LibrarySession(client: shared.client, user: shared.user)
        session.onUnauthorized = shared.onUnauthorized
        return session
    }

    var body: some View {
        Group {
            if app.session != nil {
                if let session, sharedID == app.session.map(ObjectIdentifier.init) {
                    MainView(initialAlbumID: route?.albumID, initialSearch: route?.query)
                        .environment(session)
                        .id(ObjectIdentifier(session))
                } else { ProgressView() }
            } else { RootView() }
        }
        .background(MacWindowConfiguration(asTab: route?.asTab ?? false))
        .onChange(of: app.session.map(ObjectIdentifier.init), initial: true) {
            let current = app.session.map(ObjectIdentifier.init)
            if sharedID != current {
                session = app.session.map(Self.independentSession)
                sharedID = current
            }
            if let session { Task { await session.bootstrap() } }
            else { MacQuickLook.shared.dismiss() }
        }
    }
}

/// Configure only the scene's actual window; never search NSApp.windows for a new panel.
private struct MacWindowConfiguration: NSViewRepresentable {
    let asTab: Bool
    func makeNSView(context: Context) -> NSView { WindowView(asTab: asTab) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowView: NSView {
        let asTab: Bool
        init(asTab: Bool) { self.asTab = asTab; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.tabbingIdentifier = "ImmichGallery.library"
            window?.tabbingMode = asTab ? .preferred : .automatic
        }
    }
}

struct MacAlbumWindowMenu: View {
    @Environment(\.openWindow) private var openWindow
    let albumID: String

    var body: some View {
        Button("Open Album in New Window") { openWindow(id: "main", value: MacWindowRoute(albumID: albumID)) }
        Button("Open in New Tab") { openWindow(id: "main", value: MacWindowRoute(albumID: albumID, asTab: true)) }
    }
}

struct MacIntegrationCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main", value: MacWindowRoute()) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Tab") { openWindow(id: "main", value: MacWindowRoute(asTab: true)) }
                .keyboardShortcut("t", modifiers: .command)
        }
        CommandGroup(after: .windowArrangement) {
            Button("Show Tab Bar") { NSApp.keyWindow?.toggleTabBar(nil) }
        }
    }
}

@MainActor
enum MacWindowInvalidation {
    private static let sessions = NSHashTable<LibrarySession>.weakObjects()
    static func register(_ session: LibrarySession) { sessions.add(session) }
    static func invalidate(from source: LibrarySession) {
        for session in sessions.allObjects where session !== source && session.client.apiURL == source.client.apiURL && session.client.credential == source.client.credential {
            session.invalidateMacWindowGrids()
        }
    }
}

final class MacIntegrationLifecycle: NSObject, NSApplicationDelegate {
    private var cleanupTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in MacTransferCache.prune() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        MacQuickLook.shared.dismiss()
        MacTransferCache.prune()
    }
}
