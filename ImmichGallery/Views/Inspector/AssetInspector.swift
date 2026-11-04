import MapKit
import SwiftUI

struct AssetInspector: View {
    @Environment(LibrarySession.self) private var session
    let assetID: String?

    @State private var asset: AssetResponse?
    @State private var albums: [Album] = []
    @State private var failed = false

    var body: some View {
        Group {
            if assetID == nil {
                ContentUnavailableView("No Selection", systemImage: "info.circle",
                                       description: Text("Select a single photo to see its details."))
            } else if let asset {
                details(asset)
            } else if failed {
                ContentUnavailableView("Couldn't Load Info", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(assetID ?? "")-\(session.metadata.revision)") {
            guard let assetID else { return }
            failed = false
            asset = nil
            albums = []
            do {
                asset = try await session.client.asset(assetID)
                albums = (try? await session.client.albums(containing: assetID)) ?? []
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private func details(_ asset: AssetResponse) -> some View {
        let exif = asset.exifInfo
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.originalFileName)
                        .font(.headline)
                        .textSelection(.enabled)
                    if let date = ImmichDate.parse(asset.localDateTime) {
                        Text(ImmichDate.long(date)).foregroundStyle(.secondary)
                    }
                }

                MetadataInspectorControls(asset: asset) // Metadata

                if let exif, exif.make != nil || exif.model != nil || exif.lensModel != nil {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text([exif.make, exif.model].compactMap { $0 }.joined(separator: " "))
                                .font(.callout.weight(.semibold))
                            if let lens = exif.lensModel {
                                Text(lens).font(.caption).foregroundStyle(.secondary)
                            }
                            let specs = exposureSpecs(exif)
                            if !specs.isEmpty {
                                HStack(spacing: 0) {
                                    ForEach(Array(specs.enumerated()), id: \.offset) { i, spec in
                                        if i > 0 { Divider().frame(height: 14) }
                                        Text(spec).font(.caption.monospacedDigit()).frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 6) {
                        row("Type", asset.originalMimeType ?? asset.type.rawValue.capitalized)
                        if let w = exif?.exifImageWidth ?? asset.width, let h = exif?.exifImageHeight ?? asset.height {
                            row("Dimensions", "\(w) × \(h)")
                            row("Resolution", "\(String(format: "%.1f", Double(w * h) / 1_000_000)) MP")
                        }
                        if let bytes = exif?.fileSizeInByte {
                            row("Size", bytes.formatted(.byteCount(style: .file)))
                        }
                        if let duration = asset.duration?.milliseconds, asset.type == .video {
                            row("Duration", Duration.formatMilliseconds(duration))
                        }
                    }
                }

                if let lat = exif?.latitude, let lon = exif?.longitude {
                    VStack(alignment: .leading, spacing: 6) {
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))) {
                            Marker("", coordinate: coordinate)
                        }
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 10))
                        .id("\(lat),\(lon)")
                        let place = [exif?.city, exif?.state, exif?.country].compactMap { $0 }.joined(separator: ", ")
                        if !place.isEmpty { Text(place).font(.callout) }
                    }
                }

                if let people = asset.people?.filter({ !$0.name.isEmpty }), !people.isEmpty {
                    section("People") {
                        FlowText(people.map(\.name), symbol: "person.crop.circle")
                    }
                }

                if !albums.isEmpty {
                    section("Albums") {
                        FlowText(albums.map(\.albumName), symbol: "rectangle.stack")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exposureSpecs(_ exif: Exif) -> [String] {
        var specs: [String] = []
        if let iso = exif.iso { specs.append("ISO \(iso)") }
        if let focal = exif.focalLength { specs.append("\(focal.formatted(.number.precision(.fractionLength(0...1)))) mm") }
        if let f = exif.fNumber { specs.append("ƒ\(f.formatted(.number.precision(.fractionLength(0...1))))") }
        if let t = exif.exposureTime { specs.append("\(t) s") }
        return specs
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct FlowText: View {
    let items: [String]
    let symbol: String

    init(_ items: [String], symbol: String) {
        self.items = items
        self.symbol = symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { Label($0, systemImage: symbol).font(.callout) }
        }
    }
}
