import SwiftUI
import WidgetKit

/// Library at a glance: photo, video, album and people counts and the server's storage.
struct LibraryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.libraryKind, provider: LibraryProvider()) { entry in
            LibraryWidgetView(stats: entry.stats)
        }
        .configurationDisplayName("Library")
        .description("How many photos and videos you have, and how full the server is.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LibraryEntry: TimelineEntry {
    let date: Date
    var stats: WidgetFeed.Stats?
}

struct LibraryProvider: TimelineProvider {
    private static let sample = WidgetFeed.Stats(updated: Date(), photos: 12_480, videos: 342, albums: 36, people: 58,
                                                 libraryBytes: 96_000_000_000, diskUsed: 410_000_000_000, diskSize: 1_000_000_000_000)

    func placeholder(in context: Context) -> LibraryEntry { LibraryEntry(date: Date(), stats: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        let stats = WidgetFeed.load()?.stats
        completion(LibraryEntry(date: Date(), stats: stats ?? (context.isPreview ? Self.sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        // The app reloads the widget whenever it saves new numbers.
        completion(Timeline(entries: [LibraryEntry(date: Date(), stats: WidgetFeed.load()?.stats)], policy: .never))
    }
}

struct LibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let stats: WidgetFeed.Stats?

    var body: some View {
        Group {
            if let stats {
                if family == .systemSmall { small(stats) } else { medium(stats) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack").font(.title2)
                    Text("Open Immich Gallery to see your library here.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetFeed.Link.open.url)
    }

    private func small(_ stats: WidgetFeed.Stats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Library", systemImage: "photo.stack").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            count(stats.photos, "Photos", large: true)
            count(stats.videos, "Videos", large: false)
            if let storage = storage(stats) { storageBar(storage, compact: true) }
        }
    }

    private func medium(_ stats: WidgetFeed.Stats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Library", systemImage: "photo.stack").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                count(stats.photos, "Photos", large: true)
                count(stats.videos, "Videos", large: true)
                count(stats.albums, "Albums", large: true)
                if let people = stats.people { count(people, "People", large: true) }
            }
            Spacer(minLength: 0)
            if let storage = storage(stats) { storageBar(storage, compact: false) }
            if let bytes = stats.libraryBytes {
                Text("Your library: \(bytes.formatted(.byteCount(style: .file)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func count(_ value: Int, _ label: LocalizedStringKey, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value, format: .number)
                .font(large ? .title2.weight(.semibold) : .headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func storage(_ stats: WidgetFeed.Stats) -> (used: Int64, size: Int64)? {
        guard let used = stats.diskUsed, let size = stats.diskSize, size > 0 else { return nil }
        return (used, size)
    }

    private func storageBar(_ storage: (used: Int64, size: Int64), compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: Double(storage.used), total: Double(storage.size))
                .tint(Double(storage.used) / Double(storage.size) > 0.9 ? .red : .accentColor)
            Text(compact ? "Server \(storage.used.formatted(.byteCount(style: .file)))"
                         : "Server storage: \(storage.used.formatted(.byteCount(style: .file))) of \(storage.size.formatted(.byteCount(style: .file)))")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
