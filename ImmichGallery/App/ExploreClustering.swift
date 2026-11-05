import Foundation
import MapKit

struct ExploreMapCluster: Identifiable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
    let assets: [String]
    let bbox: String
    static func make(_ markers: [ExploreMarker], latitude: Double, longitude: Double, latSpan: Double, lonSpan: Double) -> [Self] {
        guard latitude.isFinite, longitude.isFinite, latSpan.isFinite, lonSpan.isFinite else { return [] }
        let latitude = min(90, max(-90, latitude))
        let wrappedLongitude = longitude.truncatingRemainder(dividingBy: 360)
        let longitude = wrappedLongitude < -180 ? wrappedLongitude + 360 : (wrappedLongitude > 180 ? wrappedLongitude - 360 : wrappedLongitude)
        let latSpan = min(180, max(0.00001, abs(latSpan)))
        let lonSpan = min(360, max(0.00001, abs(lonSpan)))
        // Keep cell boundaries fixed between zoom levels, including small camera rounding changes.
        let latStep = pow(2, ceil(log2(max(latSpan / 12, 0.00001))))
        let lonStep = pow(2, ceil(log2(max(lonSpan / 16, 0.00001))))
        var groups: [String: [ExploreMarker]] = [:]
        for marker in markers where marker.lat.isFinite && marker.lon.isFinite && abs(marker.lat) <= 90 && abs(marker.lon) <= 180 {
            let distance = abs((marker.lon - longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
            guard abs(marker.lat - latitude) <= latSpan * 0.65, distance <= lonSpan * 0.65 else { continue }
            let key = "\(Int(floor(marker.lat / latStep))):\(Int(floor(marker.lon / lonStep)))"
            groups[key, default: []].append(marker)
        }
        return groups.values.map { markers in
            let group = markers.sorted { $0.id < $1.id }
            // An unchanged group keeps its annotation and thumbnail across zooms and server ordering changes.
            return Self(id: group[0].id, lat: group.reduce(0) { $0 + $1.lat } / Double(group.count), lon: group.reduce(0) { $0 + $1.lon } / Double(group.count), assets: group.map(\.id),
                 bbox: "\(max(-180, group.map(\.lon).min()! - 0.000001)),\(max(-90, group.map(\.lat).min()! - 0.000001)),\(min(180, group.map(\.lon).max()! + 0.000001)),\(min(90, group.map(\.lat).max()! + 0.000001))")
        }.sorted { $0.id < $1.id }
    }

    static func initialBounds(_ markers: [ExploreMarker]) -> MKMapRect? {
        let points = markers.filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }
            // Mercator cannot represent the poles; fit their nearest visible latitude instead.
            .map { MKMapPoint(CLLocationCoordinate2D(latitude: min(85, max(-85, $0.lat)), longitude: $0.lon)) }
        guard let first = points.first else { return nil }
        let bounds = points.dropFirst().reduce(MKMapRect(x: first.x, y: first.y, width: 0, height: 0)) {
            $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0))
        }
        // Leave room for thumbnails, with a useful minimum area for a single location.
        let padded = bounds.insetBy(dx: -max(bounds.width * 0.15, 10_000), dy: -max(bounds.height * 0.15, 10_000))
            .intersection(.world)
        guard !padded.isNull, !padded.isEmpty, padded.origin.x.isFinite, padded.origin.y.isFinite,
              padded.width.isFinite, padded.height.isFinite else { return nil }
        return padded
    }
}


extension ExploreMapCluster: Hashable {}
