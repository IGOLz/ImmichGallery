import MapKit
import SwiftUI

struct ExploreMapView: View {
    @Environment(LibrarySession.self) private var session
    @State private var markers: [ExploreMarker] = []
    @State private var clusters: [ExploreMapCluster] = []
    @State private var region = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 180, longitudeDelta: 360))
    @State private var favorites = false
    @State private var archived = false
    @State private var partners = true
    @State private var dateFilter = false
    @State private var after = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    @State private var before = Date()
    @State private var error: String?
    @State private var selection: ExploreMapCluster?
    @State private var clusterTask: Task<Void, Never>?
    private var filterKey: String { "\(favorites)-\(archived)-\(partners)-\(dateFilter)-\(after)-\(before)" }
    var body: some View {
        Map {
            ForEach(clusters) { cluster in
                Annotation("\(cluster.assets.count) photos", coordinate: .init(latitude: cluster.lat, longitude: cluster.lon)) {
                    Button { selection = cluster } label: {
                        RemoteThumbnail(assetID: cluster.assets.first)
                            .frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 8))
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(cluster.assets.count)").font(.caption.bold()).padding(3).background(.regularMaterial, in: Capsule())
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region; recluster() }
        .toolbar {
            Menu {
                Toggle("Favorites Only", isOn: $favorites)
                Toggle("Include Archived", isOn: $archived)
                Toggle("Include Partners", isOn: $partners)
                Toggle("Date Range", isOn: $dateFilter)
                if dateFilter {
                    DatePicker("From", selection: $after, in: ...before, displayedComponents: .date)
                    DatePicker("Through", selection: $before, in: after..., displayedComponents: .date)
                }
            } label: { Label("Map Filters", systemImage: "line.3.horizontal.decrease") }
        }
        .task(id: filterKey) {
            do {
                markers = try await session.client.exploreMarkers(favorites: favorites, archived: archived, partners: partners,
                    after: dateFilter ? Calendar.current.startOfDay(for: after) : nil,
                    before: dateFilter ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: before)) : nil)
                error = nil
                recluster()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .overlay { if let error { ContentUnavailableView("Map Unavailable", systemImage: "map", description: Text(error)) } }
        .navigationDestination(item: $selection) { cluster in
            AssetGridContainer(source: .explore(.markers(cluster.assets)), title: Text("Map Photos"))
        }
        .onDisappear { clusterTask?.cancel() }
    }
    private func recluster() {
        clusterTask?.cancel()
        let markers = markers
        let latitude = region.center.latitude, longitude = region.center.longitude
        let latSpan = region.span.latitudeDelta, lonSpan = region.span.longitudeDelta
        clusterTask = Task {
            let result = await Task.detached { ExploreMapCluster.make(markers, latitude: latitude, longitude: longitude, latSpan: latSpan, lonSpan: lonSpan) }.value
            if !Task.isCancelled { clusters = result }
        }
    }
}
