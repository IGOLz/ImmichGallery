import AppIntents
import ImageIO
import SwiftUI
import WidgetKit

@main
struct ImmichGalleryWidgets: WidgetBundle {
    var body: some Widget {
        PhotosWidget()
        PhotoMosaicWidget()
        LibraryWidget()
    }
}

/// Apple Photos–style desktop widget: one photo at a time from the source chosen in its settings.
/// The widgets read only what the app prepared (see `WidgetFeedUpdater`); they have no network access.
struct PhotosWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.photosKind, intent: PhotoWidgetIntent.self, provider: PhotosProvider(mosaic: false)) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("Photos")
        .description("Featured photos and memories, or photos from an album, a person, a place or your favorites.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        // Keep the photo when the desktop widget turns vibrant behind windows.
        .containerBackgroundRemovable(false)
    }
}

struct PhotoMosaicWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.mosaicKind, intent: PhotoWidgetIntent.self, provider: PhotosProvider(mosaic: true)) { entry in
            PhotoMosaicView(entry: entry)
        }
        .configurationDisplayName("Photo Mosaic")
        .description("Several photos at once from the source you choose.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

// MARK: Timeline

struct PhotoEntry: TimelineEntry {
    enum State { case ready, placeholder, signedOut, choose, loading, empty, noneChosen }
    let date: Date
    var state: State
    var photos: [WidgetFeed.Photo] = []
    var pool = ""
}

struct PhotosProvider: AppIntentTimelineProvider {
    let mosaic: Bool

    func placeholder(in context: Context) -> PhotoEntry { PhotoEntry(date: Date(), state: .placeholder) }

    func snapshot(for configuration: PhotoWidgetIntent, in context: Context) async -> PhotoEntry {
        let entry = entries(configuration, family: context.family, from: Date(), count: 1).first ?? PhotoEntry(date: Date(), state: .signedOut)
        return entry.state == .ready || !context.isPreview ? entry : PhotoEntry(date: Date(), state: .placeholder)
    }

    func timeline(for configuration: PhotoWidgetIntent, in context: Context) async -> Timeline<PhotoEntry> {
        let now = Date()
        let entries = entries(configuration, family: context.family, from: now, count: 6)
        guard entries.count > 1 || entries.first?.state == .ready else {
            // The app reloads the widgets as soon as it has photos.
            return Timeline(entries: entries, policy: .never)
        }
        let slot = (now.timeIntervalSince1970 / WidgetFeed.rotation).rounded(.down) * WidgetFeed.rotation
        return Timeline(entries: entries, policy: .after(Date(timeIntervalSince1970: slot + Double(entries.count) * WidgetFeed.rotation)))
    }

    private func tiles(_ family: WidgetFamily) -> Int {
        guard mosaic else { return 1 }
        return switch family {
        case .systemMedium: 3
        case .systemLarge: 4
        default: 6
        }
    }

    private func entries(_ configuration: PhotoWidgetIntent, family: WidgetFamily, from now: Date, count: Int) -> [PhotoEntry] {
        guard let manifest = WidgetFeed.load() else { return [PhotoEntry(date: now, state: .signedOut)] }
        guard let source = configuration.feedSource else { return [PhotoEntry(date: now, state: .choose)] }
        WidgetFeed.noteRequested(source)
        guard let pool = manifest.pools[source.key] else { return [PhotoEntry(date: now, state: .loading)] }
        guard !pool.photos.isEmpty else { return [PhotoEntry(date: now, state: source == .chosen ? .noneChosen : .empty)] }
        let tiles = tiles(family)
        // The mosaic has its own "Next" position, so it doesn't move a photo widget with the same source.
        let rotation = (mosaic ? "mosaic." : "") + source.key
        let offset = WidgetFeed.offset(rotation)
        let steps = min(count, max(1, pool.photos.count / tiles))
        let slot = (now.timeIntervalSince1970 / WidgetFeed.rotation).rounded(.down) * WidgetFeed.rotation
        return (0..<steps).map { step in
            let date = step == 0 ? now : Date(timeIntervalSince1970: slot + Double(step) * WidgetFeed.rotation)
            return PhotoEntry(date: date, state: .ready, photos: WidgetFeed.photos(at: date, in: pool.photos, count: tiles, offset: offset), pool: rotation)
        }
    }
}

// MARK: Views

/// Decodes only as many pixels as the widget shows (Retina), to stay within the memory limit.
private func widgetImage(_ photo: WidgetFeed.Photo, maxPixelSize: Int) -> CGImage? {
    guard let url = WidgetFeed.fileURL(photo), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary)
}

struct PhotoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    var body: some View {
        let maxPixelSize = switch family {
        case .systemSmall: 480
        case .systemMedium, .systemLarge: 900
        default: 1280
        }
        if entry.state == .ready, let photo = entry.photos.first, let image = widgetImage(photo, maxPixelSize: maxPixelSize) {
            caption(photo.caption)
                .overlay(alignment: .topTrailing) { NextPhotoButton(pool: entry.pool, compact: family == .systemSmall) }
                .containerBackground(for: .widget) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
                .widgetURL(WidgetFeed.link(for: photo).url)
        } else {
            WidgetMessage(state: entry.state)
        }
    }

    @ViewBuilder
    private func caption(_ text: String) -> some View {
        if text.isEmpty {
            Color.clear
        } else {
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Text(text)
                    .font(family == .systemSmall ? .caption.weight(.semibold) : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(family == .systemSmall ? 12 : 16)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .frame(height: family == .systemSmall ? 60 : 90)
            }
        }
    }
}

struct PhotoMosaicView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    var body: some View {
        if entry.state == .ready, !entry.photos.isEmpty {
            let columns = family == .systemLarge ? 2 : 3
            let rows = family == .systemMedium ? 1 : 2
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            tile(row * columns + column)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) { NextPhotoButton(pool: entry.pool, compact: false) }
            .containerBackground(.black, for: .widget)
            .widgetURL(WidgetFeed.Link.open.url)
        } else {
            WidgetMessage(state: entry.state)
        }
    }

    @ViewBuilder
    private func tile(_ index: Int) -> some View {
        // A pool smaller than the grid repeats from the start.
        let photo = entry.photos[index % entry.photos.count]
        Color.clear
            .overlay {
                if let image = widgetImage(photo, maxPixelSize: 600) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .widgetLink(WidgetFeed.link(for: photo).url)
    }
}

private extension View {
    func widgetLink(_ url: URL) -> some View { Link(destination: url) { self } }
}

/// Shows the next photo right away; the clock-based rotation continues from there.
struct NextPhotoButton: View {
    let pool: String
    let compact: Bool

    var body: some View {
        Button(intent: NextPhotoIntent(pool: pool)) {
            Image(systemName: "forward.fill")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.white)
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Next Photo"))
        .padding(compact ? 8 : 10)
    }
}

struct WidgetMessage: View {
    @Environment(\.widgetFamily) private var family
    let state: PhotoEntry.State

    private var text: LocalizedStringKey? {
        switch state {
        case .ready, .placeholder: nil
        case .signedOut: "Open Immich Gallery to see your photos here."
        case .loading: "Open Immich Gallery to load these photos."
        case .choose: "Edit the widget to choose what it shows."
        case .empty: "There are no photos to show here."
        case .noneChosen: "Choose photos in Immich Gallery with Show in Widget."
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(family == .systemSmall ? .title2 : .largeTitle)
            if let text {
                Text(text)
                    .font(family == .systemSmall ? .caption : .callout)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [.indigo.opacity(0.55), .teal.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(WidgetFeed.Link.open.url)
    }
}
