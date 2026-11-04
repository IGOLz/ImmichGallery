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
    var body: some View {
        Group {
            if let services = app.services {
                MacSignedInWindow(services: services, route: route)
                    .id(ObjectIdentifier(services))
            } else { RootView() }
        }
        .modifier(AccountChrome())
        .background(MacWindowConfiguration(asTab: route?.asTab ?? false))
    }
}

struct MacSignedInWindow: View {
    let services: AccountServices
    let route: MacWindowRoute?
    @State private var session: LibrarySession?
    var body: some View {
        Group {
            if let session {
                MainView(initialAlbumID: route?.albumID, initialSearch: route?.query).environment(session)
            } else { ProgressView() }
        }
        .task { if session == nil { session = LibrarySession(services: services) } }
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
