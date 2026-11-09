import Foundation

// Places: the Immich web app's places grouping (web/src/routes/(user)/places/PlacesList.svelte).
// The server sends cities by name, and groups keep that order.

enum PlacesGroupBy: String, CaseIterable, Identifiable {
    case none = "None", country = "Country"
    var id: Self { self }
    var title: LocalizedStringResource { self == .none ? "No Grouping" : "Country" }
    /// Where CollapsedGroups keeps this grouping's collapsed groups.
    var collapsingKey: String? { self == .none ? nil : rawValue }
}

struct PlacesGroup: Identifiable {
    enum Header: Hashable {
        case country(String), unknownCountry
    }
    let id: String
    let header: Header?
    var places: [AssetResponse]
}

struct PlacesArrangement {
    var groupBy = PlacesGroupBy.none

    func groups(_ places: [AssetResponse]) -> [PlacesGroup] {
        guard !places.isEmpty else { return [] }
        guard groupBy == .country else { return [PlacesGroup(id: "places", header: nil, places: places)] }
        // Countries by name, places without one last.
        let countries = Dictionary(grouping: places) { place -> String? in
            place.exifInfo?.country.flatMap { $0.isEmpty ? nil : $0 }
        }
        return countries.sorted { a, b in
            switch (a.key, b.key) {
            case let (x?, y?): x.localizedCompare(y) == .orderedAscending
            case (_?, nil): true
            default: false
            }
        }
        .map { country, members in
            // Dictionary grouping keeps each group's elements in the server's order.
            PlacesGroup(id: country.map { "country-\($0)" } ?? "country-unknown",
                        header: country.map { .country($0) } ?? .unknownCountry, places: members)
        }
    }
}
