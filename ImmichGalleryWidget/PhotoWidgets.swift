import AppIntents
import ImageIO
import SwiftUI
import WidgetKit

@main
struct ImmichGalleryWidgets: WidgetBundle {
    var body: some Widget {
        FeaturedPhotosWidget()
        FavoritePhotosWidget()
        AlbumPhotosWidget()
        PersonPhotosWidget()
        PlacePhotosWidget()
        ChosenPhotosWidget()
        PhotoMosaicWidget()
        LibraryWidget()
    }
}

// Apple Photos–style desktop widgets, one per source so the widget gallery lists them all.
// The widgets read only what the app prepared (see `WidgetFeedUpdater`); they have no network access.

private let photoFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]

private extension WidgetConfiguration {
    func photoWidget() -> some WidgetConfiguration {
        contentMarginsDisabled()
            // Keep the photo when the desktop widget turns vibrant behind windows.
            .containerBackgroundRemovable(false)
    }
}

struct FeaturedPhotosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.featuredKind, provider: FixedPhotosProvider(source: .featured)) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Featured Photos")
            .description("Today's memories and highlights from your library.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct FavoritePhotosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.favoritesKind, provider: FixedPhotosProvider(source: .favorites)) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Favorites")
            .description("Your favorite photos.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct AlbumPhotosWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.albumKind, intent: AlbumWidgetIntent.self, provider: IntentPhotosProvider<AlbumWidgetIntent>()) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Album")
            .description("Photos from an album. Right-click the widget to choose which one.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct PersonPhotosWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.personKind, intent: PersonWidgetIntent.self, provider: IntentPhotosProvider<PersonWidgetIntent>()) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Person")
            .description("Photos of a person or pet. Right-click the widget to choose who.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct PlacePhotosWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.placeKind, intent: PlaceWidgetIntent.self, provider: IntentPhotosProvider<PlaceWidgetIntent>()) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Place")
            .description("Photos taken in a place. Right-click the widget to choose where.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct ChosenPhotosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.chosenKind, provider: FixedPhotosProvider(source: .chosen)) { PhotoWidgetView(entry: $0) }
            .configurationDisplayName("Chosen Photos")
            .description("Photos you add with Show in Widget in Immich Gallery.")
            .supportedFamilies(photoFamilies)
            .photoWidget()
    }
}

struct PhotoMosaicWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFeed.mosaicKind, intent: PhotoWidgetIntent.self, provider: IntentPhotosProvider<PhotoWidgetIntent>(mosaic: true)) { PhotoMosaicView(entry: $0) }
            .configurationDisplayName("Photo Mosaic")
            .description("Several photos at once. Right-click the widget to choose which ones.")
            .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
            .photoWidget()
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

/// Entries for one source; shared by the fixed and the configurable widgets.
struct PhotoTimeline {
    let mosaic: Bool

    func snapshot(_ source: WidgetFeed.Source?, family: WidgetFamily, isPreview: Bool) -> PhotoEntry {
        let now = Date()
        let entry = entries(source, family: family, from: now, count: 1, isPreview: isPreview).first ?? PhotoEntry(date: now, state: .signedOut)
        guard entry.state != .ready, isPreview else { return entry }
        // The widget gallery: show any photo the app prepared rather than an empty widget.
        if let pool = WidgetFeed.load()?.pools.values.first(where: { !$0.photos.isEmpty }) {
            return PhotoEntry(date: now, state: .ready, photos: WidgetFeed.photos(at: now, in: pool.photos, count: tiles(family)))
        }
        return PhotoEntry(date: now, state: .placeholder)
    }

    func timeline(_ source: WidgetFeed.Source?, family: WidgetFamily) -> Timeline<PhotoEntry> {
        let now = Date()
        let entries = entries(source, family: family, from: now, count: 6, isPreview: false)
        guard entries.count > 1 || entries.first?.state == .ready else {
            // The app reloads the widgets as soon as it has photos.
            return Timeline(entries: entries, policy: .never)
        }
        let slot = (now.timeIntervalSince1970 / WidgetFeed.rotation).rounded(.down) * WidgetFeed.rotation
        return Timeline(entries: entries, policy: .after(Date(timeIntervalSince1970: slot + Double(entries.count) * WidgetFeed.rotation)))
    }

    func tiles(_ family: WidgetFamily) -> Int {
        guard mosaic else { return 1 }
        return switch family {
        case .systemMedium: 3
        case .systemLarge: 4
        default: 6
        }
    }

    private func entries(_ source: WidgetFeed.Source?, family: WidgetFamily, from now: Date, count: Int, isPreview: Bool) -> [PhotoEntry] {
        guard let manifest = WidgetFeed.load() else { return [PhotoEntry(date: now, state: .signedOut)] }
        guard let source else { return [PhotoEntry(date: now, state: .choose)] }
        if !isPreview { WidgetFeed.noteRequested(source) }
        guard let pool = manifest.pools[source.key] else {
            // A running app prepares these photos within seconds and reloads the widget.
            if !isPreview { WidgetFeed.postNeedsPhotos() }
            return [PhotoEntry(date: now, state: .loading)]
        }
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

struct FixedPhotosProvider: TimelineProvider {
    let source: WidgetFeed.Source
    private let timeline = PhotoTimeline(mosaic: false)

    func placeholder(in context: Context) -> PhotoEntry { PhotoEntry(date: Date(), state: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        completion(timeline.snapshot(source, family: context.family, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        completion(timeline.timeline(source, family: context.family))
    }
}

struct IntentPhotosProvider<Intent: PhotoSourceIntent>: AppIntentTimelineProvider {
    var mosaic = false
    private var timeline: PhotoTimeline { PhotoTimeline(mosaic: mosaic) }

    func placeholder(in context: Context) -> PhotoEntry { PhotoEntry(date: Date(), state: .placeholder) }

    func snapshot(for configuration: Intent, in context: Context) async -> PhotoEntry {
        timeline.snapshot(configuration.feedSource, family: context.family, isPreview: context.isPreview)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<PhotoEntry> {
        timeline.timeline(configuration.feedSource, family: context.family)
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
