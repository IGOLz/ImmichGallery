import MapKit
import SwiftUI

struct ExploreMapView: View {
    @Environment(LibrarySession.self) private var session
    @State private var markers: [ExploreMarker] = []
    @State private var clusters: [ExploreMapCluster] = []
    @State private var region = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 180, longitudeDelta: 360))
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 180, longitudeDelta: 360)))
    @State private var didFitMarkers = false
    @State private var filters = ExploreMapFilters()
    @State private var error: String?
    @State private var selection: ExploreMapCluster?
    @State private var clusterTask: Task<Void, Never>?
    private var filterKey: String { "\(filters.favorites)-\(filters.archived)-\(filters.partners)-\(filters.dateFilter)-\(filters.after)-\(filters.before)" }
    var body: some View {
        let filters = filters
        let session = session
        let pipeline = session.pipeline
        return Map(position: $position) {
            ForEach(clusters) { cluster in
                Annotation(String(localized: "\(cluster.assets.count) photos"), coordinate: .init(latitude: cluster.lat, longitude: cluster.lon)) {
                    ExploreMapAnnotation(cluster: cluster, pipeline: pipeline) { selection = cluster }
                        .environment(session)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region; recluster() }
        .toolbar { ToolbarItem { ExploreMapFiltersButton(filters: filters) } }
        .task(id: filterKey) {
            do {
                let loaded = try await session.client.exploreMarkers(favorites: filters.favorites, archived: filters.archived, partners: filters.partners,
                    after: filters.afterDay, before: filters.beforeDay)
                guard !Task.isCancelled else { return }
                markers = loaded
                error = nil
                if !didFitMarkers, let bounds = ExploreMapCluster.initialBounds(loaded) {
                    didFitMarkers = true
                    // Fit the source markers once; fitting clusters feeds camera changes back into clustering.
                    if !position.positionedByUser {
                        region = MKCoordinateRegion(bounds)
                        position = .rect(bounds)
                    }
                }
                recluster()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .overlay { if let error { ContentUnavailableView("Map Unavailable", systemImage: "map", description: Text(error)) } }
        .navigationDestination(item: $selection) { cluster in
            AssetGridContainer(source: .explore(.map(ExploreMapQuery(bbox: cluster.bbox, favorites: filters.favorites, archived: filters.archived, partners: filters.partners,
                after: filters.afterDay, before: filters.beforeDay))), title: Text("Map Photos"))
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
            if !Task.isCancelled, clusters != result { clusters = result }
        }
    }
}

@MainActor @Observable
final class ExploreMapFilters {
    var favorites = false
    var archived = false
    var partners = true
    var dateFilter = false
    var after = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    var before = Date()

    var afterDay: Date? { dateFilter ? Calendar.current.startOfDay(for: after) : nil }
    var beforeDay: Date? { dateFilter ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: before)) : nil }
}

/// Takes only a stable reference: on macOS 15 a toolbar item whose inputs change is rebuilt,
/// which dismisses its popover after every filter change.
private struct ExploreMapFiltersButton: View {
    let filters: ExploreMapFilters
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Label("Map Filters", systemImage: "line.3.horizontal.decrease") }
            .popover(isPresented: $showing) { ExploreMapFiltersForm(filters: filters) }
    }
}

private struct ExploreMapFiltersForm: View {
    @Bindable var filters: ExploreMapFilters
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Favorites Only", isOn: $filters.favorites)
            Toggle("Include Archived", isOn: $filters.archived)
            Toggle("Include Partners", isOn: $filters.partners)
            Toggle("Date Range", isOn: $filters.dateFilter)
            if filters.dateFilter {
                DatePicker("From", selection: $filters.after, in: ...filters.before, displayedComponents: .date)
                DatePicker("Through", selection: $filters.before, in: filters.after..., displayedComponents: .date)
            }
        }.padding().frame(width: 300)
    }
}
