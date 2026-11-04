import Foundation

@main struct ExploreChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        let prefs = try decoder.decode(ExplorePreferences.self, from: Data(#"{"memories":{"enabled":false},"tags":{"enabled":true}}"#.utf8))
        precondition(prefs.memories?.enabled == false && prefs.tags?.enabled == true && prefs.folders == nil)
        let status = try decoder.decode(ExploreAuthStatus.self, from: Data(#"{"pinCode":true,"password":true,"isElevated":false}"#.utf8))
        precondition(!status.isElevated)
        let tree = ExploreFolderNode.tree(["/data/photos/2024", "/data/photos/2025", "/data/photos/2024", "/data/videos"])
        precondition(tree.count == 1 && tree[0].id == "/data")
        precondition(tree[0].children?.count == 2)
        precondition(tree[0].children?.first?.children?.map(\.name) == ["2024", "2025"])
        let markers = (0..<50_000).map { i in
            ExploreMarker(id: String(i), lat: Double(i % 180) - 89.5, lon: Double(i % 360) - 179.5)
        }
        let clusters = ExploreMapCluster.make(markers, latitude: 0, longitude: 0, latSpan: 180, lonSpan: 360)
        precondition(clusters.count <= 400)
        precondition(clusters.flatMap(\.assets).count == markers.count)
        let near = ExploreMapCluster.make(markers, latitude: 0, longitude: 0, latSpan: 10, lonSpan: 10)
        precondition(near.count < clusters.count)
        let dateline = [ExploreMarker(id: "east", lat: 0, lon: 179.9), ExploreMarker(id: "west", lat: 0, lon: -179.9)]
        precondition(ExploreMapCluster.make(dateline, latitude: 0, longitude: 180, latSpan: 10, lonSpan: 10).flatMap(\.assets).count == 2)
        print("Explore checks passed: preferences, auth, folder deduplication, 50,000-marker clustering, dateline")
    }
}
