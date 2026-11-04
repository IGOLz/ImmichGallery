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
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

struct RootView: View {
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
        .task { await app.restore() }
    }
}

// MARK: - Menu commands

extension FocusedValues {
    @Entry var gridModel: AssetGridModel?
}

struct AppCommands: Commands {
    let app: AppModel
    @FocusedValue(\.gridModel) private var grid
    @AppStorage("gridThumbnailSize") private var thumbnailSize = GridMetrics.defaultSize
    @AppStorage("showInspector") private var showInspector = false

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            if app.session != nil {
                Button("Sign Out…") { Task { await app.signOut() } }
            }
        }

        CommandGroup(after: .importExport) {
            Button("Export Unmodified Original…") {
                if let grid { Exporter.exportOriginals(grid.selectedItems.map(\.id), session: app.session) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(grid?.selection.isEmpty ?? true)
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
            Button("Refresh") {
                if let session = app.session {
                    session.pipeline.removeAll()
                    session.metadata.revision += 1
                    session.metadata.imageRevision += 1
                }
                if let grid { Task { await grid.reload() } }
            }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(grid == nil)
            Divider()
            Button(showInspector ? "Hide Info" : "Show Info") { showInspector.toggle() }
                .keyboardShortcut("i", modifiers: .command)
            Divider()
        }

        CommandMenu("Image") {
            if let session = app.session {
                let metadataIDs = grid?.viewerID.map { [$0] } ?? Array(grid?.selection ?? [])
                MetadataMenuItems(ids: metadataIDs, canEditImage: true, menuBarShortcuts: true)
                    .environment(session)
                    .disabled(metadataIDs.isEmpty || session.metadata.busy || grid?.source == .trash)
                Divider()
            }
            let ids = grid?.selectedItems.map(\.id) ?? []
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
