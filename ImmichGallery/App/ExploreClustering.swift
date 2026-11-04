import Foundation

struct ExploreMapCluster: Identifiable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
    let assets: [String]
    static func make(_ markers: [ExploreMarker], latitude: Double, longitude: Double, latSpan: Double, lonSpan: Double) -> [Self] {
        let latStep = max(latSpan / 12, 0.00001)
        let lonStep = max(lonSpan / 16, 0.00001)
        var groups: [String: [ExploreMarker]] = [:]
        for marker in markers where marker.lat.isFinite && marker.lon.isFinite && abs(marker.lat) <= 90 && abs(marker.lon) <= 180 {
            let distance = abs((marker.lon - longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
            guard abs(marker.lat - latitude) <= latSpan * 0.65, distance <= lonSpan * 0.65 else { continue }
            let key = "\(Int(floor(marker.lat / latStep))):\(Int(floor(marker.lon / lonStep)))"
            groups[key, default: []].append(marker)
        }
        return groups.map { key, group in
            Self(id: key, lat: group.reduce(0) { $0 + $1.lat } / Double(group.count), lon: group.reduce(0) { $0 + $1.lon } / Double(group.count), assets: group.map(\.id))
        }.sorted { $0.id < $1.id }
    }
}


extension ExploreMapCluster: Hashable {}
