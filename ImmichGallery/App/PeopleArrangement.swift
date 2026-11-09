import Foundation

// People: the favorite and hidden filters of the Immich web app's people page (PeopleFilterModal.svelte).
// Immich v3.3 filters on the server; older servers send every page and the app filters it. Order stays
// the server's: favorites, then named people, then by how often they appear.

enum PeopleShow: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", hidden = "Hidden"
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All People"
        case .favorites: "Favorites"
        case .hidden: "Hidden People"
        }
    }
}

struct PeopleArrangement: Equatable {
    var show = PeopleShow.all
    var includeHidden = false

    var isFiltered: Bool { show != .all || includeHidden }
    var withHidden: Bool { includeHidden || show == .hidden }

    func includes(isFavorite: Bool?, isHidden: Bool) -> Bool {
        switch show {
        case .all: withHidden || !isHidden
        case .favorites: isFavorite == true && (withHidden || !isHidden)
        case .hidden: isHidden
        }
    }

    /// The filters for `GET /people`, which Immich added in v3.3.
    func filters(server version: ServerVersion?) -> [String: String] {
        guard let version, version.major > 3 || (version.major == 3 && version.minor >= 3) else { return [:] }
        switch show {
        case .all: return [:]
        case .favorites: return ["isFavorite": "true"]
        case .hidden: return ["isHidden": "true"]
        }
    }
}
