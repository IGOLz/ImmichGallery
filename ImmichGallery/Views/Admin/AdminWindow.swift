import SwiftUI

struct AdminScene: Scene {
    let app: AppModel
    var body: some Scene {
        Window("Administration", id: "admin") { AdminWindow().environment(app) }
            .defaultSize(width: 1000, height: 700)
            .commandsRemoved()
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
    }
}

struct AdminCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appSettings) {
            if app.session?.user?.isAdmin == true {
                Button("Administration…") { openWindow(id: "admin") }
                    .keyboardShortcut("a", modifiers: [.command, .option])
            }
        }
    }
}

struct AdminWindow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        Group {
            if let session = app.session, session.user?.isAdmin == true {
                AdminView(session: session).id(ObjectIdentifier(session))
            } else {
                ContentUnavailableView("Administrator Access Required", systemImage: "lock.shield")
            }
        }
        .frame(minWidth: 850, minHeight: 560)
        .onChange(of: app.session?.user?.isAdmin) { _, value in
            if value != true { dismissWindow(id: "admin") }
        }
    }
}

private struct AdminView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model: AdminModel
    @State private var pending: AdminConfirmation?
    @State private var userEditor: AdminUserEditorItem?
    @State private var libraryEditor: AdminLibraryEditorItem?
    init(session: LibrarySession) { _model = State(initialValue: AdminModel(session: session)) }

    var body: some View {
        Group {
            if model.authorized {
                NavigationSplitView {
                    List(selection: $model.section) {
                        ForEach(AdminModel.Section.allCases.filter { !model.unavailable.contains($0) }) { section in
                            Label(section.rawValue, systemImage: section.icon).tag(section)
                        }
                    }
                    .navigationTitle("Administration")
                    .disabled(model.busy)
                } detail: {
                    detail
                        .navigationTitle(model.section.rawValue)
                        .toolbar {
                            if model.busy { ProgressView().controlSize(.small) }
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                                .disabled(model.busy)
                            if model.section == .users {
                                Button("New User", systemImage: "person.badge.plus") { userEditor = .init(user: nil) }
                                    .disabled(model.busy)
                            }
                            if model.section == .libraries {
                                Button("New Library", systemImage: "plus") { libraryEditor = .init(library: nil) }
                                    .disabled(model.busy || model.users.filter { !$0.isDeleted }.isEmpty)
                            }
                        }
                }
            } else { ContentUnavailableView("Administrator Access Required", systemImage: "lock.shield") }
        }
        .onChange(of: model.authorized) { _, value in
            if !value { dismissWindow(id: "admin") }
        }
        .task(id: model.section) {
            await model.refresh()
            while !Task.isCancelled && model.section == .queues && model.authorized && !model.unavailable.contains(.queues) {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await model.refresh()
            }
        }
        .alert("Administration", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog(pending?.title ?? "Confirm", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let action = pending {
                Button(action.button, role: .destructive) {
                    pending = nil
                    Task { await model.perform(action.operation) }
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(pending?.message ?? "") }
        .sheet(item: $userEditor) { item in AdminUserEditor(model: model, user: item.user) }
        .sheet(item: $libraryEditor) { item in AdminLibraryEditor(model: model, library: item.library) }
        .sheet(isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView { Text(model.notice ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Done") { model.notice = nil }.keyboardShortcut(.defaultAction)
            }.padding().frame(width: 540, height: 350)
        }
    }

    @ViewBuilder private var detail: some View {
        if model.unavailable.contains(model.section) {
            ContentUnavailableView("Unavailable on This Server", systemImage: "server.rack")
        } else {
            switch model.section {
            case .overview:
                Form {
                    ForEach(model.overview.keys.sorted(), id: \.self) { key in
                        Section(key) { AdminValueView(value: model.overview[key]!) }
                    }
                }.formStyle(.grouped)
            case .settings:
                Form {
                    Section {
                        Text("Server configuration is read-only.").foregroundStyle(.secondary)
                        if let settings = model.settings { AdminValueView(value: settings) }
                    }
                }.formStyle(.grouped)
            case .users: users
            case .libraries: libraries
            case .queues: queues
            }
        }
    }

    private var users: some View {
        List(model.users) { user in
            HStack {
                VStack(alignment: .leading) {
                    Text(user.name).font(.headline)
                    Text(user.email).foregroundStyle(.secondary)
                    if user.isDeleted { Text("Deleted · \(user.status ?? "pending removal")").foregroundStyle(.red) }
                    else if user.isAdmin { Text("Administrator").foregroundStyle(.secondary) }
                    Text("Used: \(ByteCountFormatter.string(fromByteCount: user.quotaUsageInBytes ?? 0, countStyle: .file)) · Quota: \(user.quotaSizeInBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unlimited")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Actions") {
                    if user.isDeleted {
                        Button("Restore User") { Task { await model.perform { try await model.session.client.adminRestoreUser(user.id) } } }
                            .disabled(user.status == "removing")
                    } else {
                        Button("Edit User…") { userEditor = .init(user: user) }
                        Button("Delete User…", role: .destructive) { deleteUser(user, force: false) }
                        Button("Force Delete User…", role: .destructive) { deleteUser(user, force: true) }
                    }
                }.disabled(model.busy || user.id == model.session.user?.id)
            }.padding(.vertical, 5)
        }
    }

    private func deleteUser(_ user: AdminUser, force: Bool) {
        pending = .init(title: "Delete \(user.name)?", button: force ? "Force Delete" : "Delete User",
                        message: force ? "Force deletion can permanently remove this user's assets. This cannot be undone once removal starts." : "This user will be scheduled for deletion. Restore is available until the server removes the account.") {
            try await model.session.client.adminDeleteUser(user.id, force: force)
        }
    }

    private var libraries: some View {
        List {
            if model.libraries.isEmpty { Text("No external libraries.").foregroundStyle(.secondary) }
            ForEach(model.libraries) { library in
                HStack {
                    VStack(alignment: .leading) {
                        Text(library.name).font(.headline)
                        Text("\(library.assetCount) assets · \(model.users.first { $0.id == library.ownerId }?.name ?? library.ownerId)")
                            .foregroundStyle(.secondary)
                        Text(library.importPaths.joined(separator: "\n")).font(.caption)
                    }
                    Spacer()
                    Menu("Actions") {
                        Button("Edit Library…") { libraryEditor = .init(library: library) }
                        Button("Scan Library") {
                            Task { await model.perform {
                                try await model.session.client.adminScanLibrary(library.id)
                                model.notice = "Library scan queued. Progress is shown in Jobs."
                            } }
                        }
                        Button("Statistics…") {
                            Task { await model.perform {
                                let value: AdminValue = try await model.session.client.get("libraries/\(library.id)/statistics")
                                model.notice = value.readable
                            } }
                        }
                        Button("Delete Library…", role: .destructive) {
                            pending = .init(title: "Delete \(library.name)?", button: "Delete Library", message: "The server will remove this library's assets from Immich. Original files on disk are preserved.") {
                                try await model.session.client.adminDeleteLibrary(library.id)
                            }
                        }
                    }.disabled(model.busy)
                }.padding(.vertical, 5)
            }
        }
    }

    private var queues: some View {
        List(model.queues) { queue in
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(queue.name).font(.headline)
                    Text(queue.isPaused ? "Paused" : "Running").foregroundStyle(.secondary)
                    Text("Active \(queue.statistics.active) · Waiting \(queue.statistics.waiting) · Paused \(queue.statistics.paused) · Failed \(queue.statistics.failed) · Delayed \(queue.statistics.delayed) · Completed \(queue.statistics.completed)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Actions") {
                    Button(queue.isPaused ? "Resume" : "Pause") { queueCommand(queue, queue.isPaused ? "resume" : "pause") }
                    if model.canStart(queue) {
                        Button(queue.name == "library" ? "Scan Libraries" : queue.name == "sidecar" ? "Discover Sidecars" : "Start Missing Jobs") { queueCommand(queue, "start") }
                        if queue.canStartAll {
                            Button("Process All Assets…") {
                                pending = .init(title: "Reprocess all assets?", button: "Process All", message: "This can take a long time. Face detection and recognition will reset existing face data; sidecar jobs will sync metadata.") {
                                    try await model.session.client.adminQueueCommand(queue.name, command: "start", force: true)
                                }
                            }
                        }
                    }
                    Button("Clear Queue…", role: .destructive) {
                        pending = .init(title: "Clear \(queue.name)?", button: "Clear Queue", message: "Waiting and failed jobs will be removed. Active jobs may finish.") {
                            try await model.session.client.adminQueueCommand(queue.name, command: "empty")
                        }
                    }
                }.disabled(model.busy)
            }.padding(.vertical, 5)
        }
        .safeAreaInset(edge: .bottom) { Text("Refreshes every 10 seconds while Jobs is open.").font(.caption).foregroundStyle(.secondary).padding(8) }
    }
    private func queueCommand(_ queue: AdminQueue, _ command: String) {
        Task { await model.perform { try await model.session.client.adminQueueCommand(queue.name, command: command) } }
    }
}

private struct AdminConfirmation {
    let title: String
    let button: String
    let message: String
    let operation: () async throws -> Void
}
private struct AdminUserEditorItem: Identifiable { let id = UUID(); let user: AdminUser? }
private struct AdminLibraryEditorItem: Identifiable { let id = UUID(); let library: AdminLibrary? }

struct AdminValueView: View {
    let value: AdminValue
    var body: some View {
        switch value {
        case .object(let fields):
            ForEach(fields.keys.sorted(), id: \.self) { key in
                if ["password", "secret", "token", "apikey", "clientsecret"].contains(where: { key.lowercased().contains($0) }) {
                    LabeledContent(key, value: "Hidden")
                } else {
                    switch fields[key]! {
                    case .object, .array:
                        DisclosureGroup(key) { AdminValueView(value: fields[key]!) }
                    default: LabeledContent(key, value: fields[key]!.display).textSelection(.enabled)
                    }
                }
            }
        case .array(let values):
            ForEach(values.indices, id: \.self) { index in
                AdminValueView(value: values[index])
            }
        default: Text(value.display).textSelection(.enabled)
        }
    }
}

extension AdminValue {
    var readable: String {
        switch self {
        case .object(let fields): fields.keys.sorted().map { "\($0): \(fields[$0]!.readable)" }.joined(separator: "\n")
        case .array(let values): values.map(\.readable).joined(separator: "\n\n")
        default: display
        }
    }
}
