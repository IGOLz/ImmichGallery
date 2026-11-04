import SwiftUI

@main
struct ImmichGalleryApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        Window("Immich Gallery", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(app: app); AdminCommands(app: app) }

        AdminScene(app: app) // Admin

        Settings {
            AccountSettingsTabs() // Account
                .environment(app)
        }
    }
}

struct RootView: View {
    @State private var changingPassword = false
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView().controlSize(.large)
            case .signedOut:
                LoginView()
            case .signedIn(let session):
                MainView()
                    .environment(session)
                    .id(ObjectIdentifier(session))
            }
        }
        .safeAreaInset(edge: .top) {
            if app.session?.user?.shouldChangePassword == true {
                HStack {
                    Text("Your server asks you to change your password.")
                    Button("Change Password…") { changingPassword = true }
                }.padding(8).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .sheet(isPresented: $changingPassword) {
            if let session = app.session {
                VStack {
                    AccountSecurityView(session: session)
                    Button("Done") { changingPassword = false }.padding()
                }.frame(width: 640, height: 650)
            }
        }
        .task { await app.restore() }
        .alert("Account Error", isPresented: Binding(get: { app.accountError != nil }, set: { if !$0 { app.accountError = nil } })) {
            Button("OK") { app.accountError = nil }
        } message: { Text(app.accountError ?? "") }
    }
}

// MARK: - Menu commands

struct SearchActions {
    var find: () -> Void
    var filters: () -> Void
}

extension FocusedValues {
    @Entry var searchActions: SearchActions?
    @Entry var gridModel: AssetGridModel?
}

struct AppCommands: Commands {
    let app: AppModel
    @FocusedValue(\.searchActions) private var searchActions
    @FocusedValue(\.gridModel) private var grid
    @AppStorage("gridThumbnailSize") private var thumbnailSize = GridMetrics.defaultSize
    @AppStorage("showInspector") private var showInspector = false

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            if app.session != nil {
                Button("Sign Out…") { Task { await app.signOut() } }
            }
        }

        CommandGroup(after: .newItem) {
            Button("New Album…") { app.session?.albumActions.newAlbum() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(app.session == nil)
        } // Albums

        CommandGroup(after: .importExport) {
            Button("Export Unmodified Original…") {
                if let grid { Exporter.exportOriginals(grid.selectedItems.map(\.id), session: app.session) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(grid?.selection.isEmpty ?? true)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { searchActions?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchActions == nil)
            Button("Search Filters…") { searchActions?.filters() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(searchActions == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Select All Photos") { grid?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(grid == nil || grid?.viewerID != nil)
        }

        CommandGroup(before: .sidebar) {
            Button("Zoom In") { thumbnailSize = GridMetrics.zoomIn(thumbnailSize) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { thumbnailSize = GridMetrics.zoomOut(thumbnailSize) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button("Refresh") { if let grid { Task { await grid.reload() } } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(grid == nil)
            Divider()
            Button(showInspector ? "Hide Info" : "Show Info") { showInspector.toggle() }
                .keyboardShortcut("i", modifiers: .command)
            Divider()
        }

        CommandMenu("Image") {
            let ids = grid?.selectedItems.map(\.id) ?? []
            if let session = app.session { AlbumSelectionMenu(session: session, model: grid, ids: ids) } // Albums
            // "." and ⌘⌫ are handled by the grid/viewer so they don't steal keys from text fields.
            Button("Favorite  (.)") { if let grid { Task { await grid.toggleFavorite(ids) } } }
                .disabled(ids.isEmpty)
            if grid?.source == .archive {
                Button("Unarchive") { if let grid { Task { await grid.setArchived(ids, false) } } }
                    .disabled(ids.isEmpty)
            } else {
                Button("Archive") { if let grid { Task { await grid.setArchived(ids, true) } } }
                    .keyboardShortcut("a", modifiers: [.command, .control])
                    .disabled(ids.isEmpty || grid?.source == .trash)
            }
        }
    }
}
