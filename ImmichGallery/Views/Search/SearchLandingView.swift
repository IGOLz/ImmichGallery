import SwiftUI

struct SearchLandingView<Controls: View>: View {
    let pipeline: ImagePipeline
    let query: SearchQuery
    let recent: [SearchQuery]
    let places: [SearchExploreGroup.Item]
    let controls: Controls
    let select: (SearchQuery) -> Void
    let clearHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search Your Photos")
                        .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(introduction)
                        .font(.body).foregroundStyle(.secondary)
                    controls.padding(.top, 8)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { quickFilters }
                    VStack(alignment: .leading, spacing: 10) { quickFilters }
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Searches").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Clear History", action: clearHistory)
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 10) {
                            ForEach(Array(recent.prefix(6).enumerated()), id: \.offset) { _, entry in
                                Button { select(entry) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.title3).foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.text.isEmpty ? entry.chips.joined(separator: ", ") : entry.text)
                                                .fontWeight(.medium).lineLimit(1)
                                            Text(entry.text.isEmpty ? String(localized: "Filtered Search")
                                                 : entry.chips.isEmpty ? String(localized: entry.mode.title) : entry.chips.joined(separator: ", "))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .help(([entry.text] + entry.chips).filter { !$0.isEmpty }.joined(separator: ", "))
                            }
                        }
                    }
                }

                if !places.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Places in Your Library").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)], alignment: .leading, spacing: 20) {
                            ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                                Button {
                                    var next = query
                                    next.city = place.value
                                    select(next)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        RemoteThumbnail(pipeline: pipeline, assetID: place.data.id, size: .preview)
                                            .aspectRatio(1.35, contentMode: .fit)
                                            .clipShape(.rect(cornerRadius: 10))
                                        Label(place.value, systemImage: "mappin")
                                            .font(.headline).lineLimit(1)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .help(place.value)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var introduction: LocalizedStringKey {
        switch query.mode {
        case .context: "Find a scene, a place, or a detail you remember."
        case .fileName: "Search by file name or extension."
        case .description: "Find words in your photo descriptions."
        case .ocr: "Find text captured in your photos."
        }
    }

    private var quickFilters: some View {
        Group {
            quickFilter("Favorites", icon: "heart") { $0.favorites = true }
            quickFilter("Photos", icon: "photo") { $0.mediaType = "IMAGE" }
            quickFilter("Videos", icon: "video") { $0.mediaType = "VIDEO" }
        }
    }

    private func quickFilter(_ title: LocalizedStringKey, icon: String, update: @escaping (inout SearchQuery) -> Void) -> some View {
        Button {
            var next = query
            update(&next)
            select(next)
        } label: {
            Label(title, systemImage: icon).padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule)
    }
}
