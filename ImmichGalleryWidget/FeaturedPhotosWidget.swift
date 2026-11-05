import ImageIO
import SwiftUI
import WidgetKit

@main
struct ImmichGalleryWidgets: WidgetBundle {
    var body: some Widget { FeaturedPhotosWidget() }
}

/// Apple Photos–style desktop widget: one photo at a time, from today's memories and the library.
/// It reads only what the app prepared (see `WidgetFeedUpdater`); it has no network access.
struct FeaturedPhotosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.kind, provider: FeaturedPhotosProvider()) { entry in
            FeaturedPhotoView(entry: entry)
        }
        .configurationDisplayName("Featured Photos")
        .description("Memories and highlights from your Immich library.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        // Keep the photo when the desktop widget turns vibrant behind windows.
        .containerBackgroundRemovable(false)
    }
}

struct FeaturedPhotoEntry: TimelineEntry {
    let date: Date
    var photo: WidgetFeed.Photo?
    var isPlaceholder = false
}

struct FeaturedPhotosProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeaturedPhotoEntry {
        FeaturedPhotoEntry(date: Date(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeaturedPhotoEntry) -> Void) {
        let photos = WidgetFeed.load()?.photos ?? []
        completion(FeaturedPhotoEntry(date: Date(), photo: WidgetFeed.photo(at: Date(), in: photos), isPlaceholder: photos.isEmpty && context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeaturedPhotoEntry>) -> Void) {
        let photos = WidgetFeed.load()?.photos ?? []
        guard !photos.isEmpty else {
            // The app reloads the widget as soon as it has photos.
            completion(Timeline(entries: [FeaturedPhotoEntry(date: Date())], policy: .never))
            return
        }
        let now = Date()
        let slot = (now.timeIntervalSince1970 / WidgetFeed.rotation).rounded(.down) * WidgetFeed.rotation
        let steps = min(6, photos.count)
        let entries = (0..<steps).map { step in
            let date = step == 0 ? now : Date(timeIntervalSince1970: slot + Double(step) * WidgetFeed.rotation)
            return FeaturedPhotoEntry(date: date, photo: WidgetFeed.photo(at: date, in: photos))
        }
        let end = Date(timeIntervalSince1970: slot + Double(steps) * WidgetFeed.rotation)
        completion(Timeline(entries: entries, policy: .after(end)))
    }
}

struct FeaturedPhotoView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FeaturedPhotoEntry

    private var image: CGImage? {
        guard let photo = entry.photo, let url = WidgetFeed.fileURL(photo),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decode only as many pixels as the widget shows (Retina), to stay within the memory limit.
        let maxPixelSize = switch family {
        case .systemSmall: 480
        case .systemMedium, .systemLarge: 900
        default: 1280
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    var body: some View {
        let image = image
        Group {
            if let image, let photo = entry.photo {
                caption(photo.caption)
                    .containerBackground(for: .widget) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    .widgetURL(WidgetFeed.link(for: photo).url)
            } else {
                emptyState
                    .containerBackground(for: .widget) {
                        LinearGradient(colors: [.indigo.opacity(0.55), .teal.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .widgetURL(WidgetFeed.Link.open.url)
            }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(family == .systemSmall ? .title2 : .largeTitle)
            if !entry.isPlaceholder {
                Text("Open Immich Gallery to see your photos here.")
                    .font(family == .systemSmall ? .caption : .callout)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
