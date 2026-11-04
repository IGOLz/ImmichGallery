import SwiftUI

struct AlbumActivityPanel: View {
    @Environment(LibrarySession.self) private var session
    let album: AlbumDetails
    let assetID: String?
    @State private var activities: [AlbumActivity] = []
    @State private var statistics: AlbumActivityStatistics?
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?
    @State private var unavailable = false

    private var ownLike: AlbumActivity? {
        activities.first { $0.type == "like" && $0.user.id == session.user?.id && $0.assetId == assetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(assetID == nil ? "Album Activity" : "Photo Activity").font(.headline)
            if unavailable { Text("Activity is unavailable on this server.").foregroundStyle(.secondary) }
            else if album.isActivityEnabled == true {
                HStack {
                    Button {
                        let like = ownLike
                        mutate {
                            if let like { try await session.client.deleteAlbumActivity(like.id) }
                            else { _ = try await session.client.createAlbumActivity(album.id, assetID: assetID, comment: nil) }
                        }
                    } label: { Label("\(statistics?.likes ?? 0)", systemImage: ownLike == nil ? "heart" : "heart.fill") }
                    Text("\(statistics?.comments ?? 0) comments").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh Activity")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(activities) { activity in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(activity.user.name).font(.callout.bold())
                                    Spacer()
                                    if activity.user.id == session.user?.id || album.isOwner(session.user?.id) {
                                        Button(role: .destructive) { mutate { try await session.client.deleteAlbumActivity(activity.id) } }
                                        label: { Image(systemName: "trash").font(.caption) }.buttonStyle(.borderless).help("Delete Activity")
                                    }
                                }
                                Text(activity.comment ?? "Liked \(activity.assetId == nil ? "the album" : "a photo")").font(.callout)
                                if let date = ImmichDate.parse(activity.createdAt) { Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                TextField("Add a comment", text: $comment, axis: .vertical).lineLimit(1...4)
                Button("Post Comment") {
                    let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    mutate {
                        _ = try await session.client.createAlbumActivity(album.id, assetID: assetID, comment: text)
                        comment = ""
                    }
                }.disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(16).disabled(busy)
        .task(id: assetID) { await load() }
    }

    private func load() async {
        guard album.isActivityEnabled == true else { return }
        do {
            async let list = session.client.albumActivities(album.id, assetID: assetID)
            async let counts = session.client.albumActivityStatistics(album.id, assetID: assetID)
            activities = try await list
            statistics = try await counts
            error = nil
        } catch {
            if case ImmichError.http(404, _) = error { unavailable = true }
            session.handle(error); self.error = error.localizedDescription
        }
    }

    private func mutate(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await action(); await load() }
            catch { session.handle(error); self.error = error.localizedDescription }
        }
    }
}
