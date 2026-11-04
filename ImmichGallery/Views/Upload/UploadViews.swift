import SwiftUI
import UniformTypeIdentifiers

struct UploadCommands: Commands {
    let app: AppModel
    var body: some Commands {
        CommandGroup(before: .importExport) {
            Button("Import…") { app.session?.upload.chooseFiles() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(app.session == nil)
        }
    }
}

struct UploadToolbar: ToolbarContent {
    @Bindable var queue: UploadQueue
    var body: some ToolbarContent {
        ToolbarItem {
            Button { queue.showingProgress.toggle() } label: {
                if queue.isRunning {
                    ProgressView(value: Double(queue.completed), total: Double(max(1, queue.items.count)))
                        .progressViewStyle(.circular).controlSize(.small)
                        .accessibilityLabel("Importing \(queue.completed) of \(queue.items.count)")
                } else {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            .help("Import photos and videos")
            .popover(isPresented: $queue.showingProgress) { UploadProgressView(queue: queue) }
        }
    }
}

private struct UploadProgressView: View {
    @Bindable var queue: UploadQueue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Import").font(.headline)
                Spacer()
                Button("Import…") { queue.chooseFiles() }.disabled(queue.discovering)
            }
            if queue.discovering { ProgressView("Scanning files…") }
            if let error = queue.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if queue.unreadableCount > 0 { Text("\(queue.unreadableCount) items could not be read").foregroundStyle(.orange) }
            if queue.unsupportedCount > 0 { Text("\(queue.unsupportedCount) unsupported files ignored").foregroundStyle(.secondary) }
            if queue.items.isEmpty {
                Text("Choose files or drop photos, videos, or folders onto the window. Drop onto an album to import there.")
                    .foregroundStyle(.secondary)
            } else {
                Text(queue.summary).font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(queue.items) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.url.lastPathComponent).lineLimit(1).help(item.url.path)
                                Text(item.state.title).font(.caption).foregroundStyle(.secondary)
                                if item.response?.isTrashed == true { Text("(in Recently Deleted)").font(.caption).foregroundStyle(.secondary) }
                                if item.state == .uploading {
                                    ProgressView(value: Double(item.sent), total: Double(max(1, item.total)))
                                    Text("\(ByteCountFormatter.string(fromByteCount: item.sent, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file))")
                                        .font(.caption).monospacedDigit()
                                }
                                if let error = item.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                            }
                        }
                    }
                }.frame(maxHeight: 320)
                HStack {
                    if queue.isRunning { Button("Cancel All", role: .cancel) { queue.cancelAll() } }
                    else {
                        Button("Retry Failed") { queue.retryFailed() }
                            .disabled(queue.failed + queue.cancelled == 0)
                        Spacer()
                        Button("Clear") { queue.clear() }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

struct UploadDropModifier: ViewModifier {
    let queue: UploadQueue
    var albumID: String?
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                        }
                        if let url, url.isFileURL { urls.append(url) }
                    }
                    if !urls.isEmpty { queue.enqueue(urls, albumID: albumID) }
                    else { queue.lastError = String(localized: "The dropped files could not be read. Try Import… instead.") }
                }
                return !providers.isEmpty
            }
            .overlay { if targeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).allowsHitTesting(false) } }
    }
}
