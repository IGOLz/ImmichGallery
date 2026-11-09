import Foundation

/// People: the Immich web app's favorite and hidden filters, on the server from v3.3 and in the app before.
@main struct PeopleArrangementChecks {
    static func main() throws {
        // Default: hidden people stay out, as before.
        let all = PeopleArrangement()
        precondition(!all.isFiltered && !all.withHidden)
        precondition(all.includes(isFavorite: nil, isHidden: false) && !all.includes(isFavorite: true, isHidden: true))
        let everyone = PeopleArrangement(includeHidden: true)
        precondition(everyone.isFiltered && everyone.withHidden && everyone.includes(isFavorite: false, isHidden: true))

        let favorites = PeopleArrangement(show: .favorites)
        precondition(favorites.includes(isFavorite: true, isHidden: false))
        precondition(!favorites.includes(isFavorite: nil, isHidden: false) && !favorites.includes(isFavorite: true, isHidden: true))
        precondition(PeopleArrangement(show: .favorites, includeHidden: true).includes(isFavorite: true, isHidden: true))

        let hidden = PeopleArrangement(show: .hidden)
        precondition(hidden.withHidden && hidden.includes(isFavorite: nil, isHidden: true) && !hidden.includes(isFavorite: true, isHidden: false))

        // Server filters only where Immich understands them.
        let v32 = ServerVersion(major: 3, minor: 2, patch: 9), v33 = ServerVersion(major: 3, minor: 3, patch: 0)
        let v4 = ServerVersion(major: 4, minor: 0, patch: 0)
        precondition(favorites.filters(server: v32).isEmpty && favorites.filters(server: nil).isEmpty)
        precondition(favorites.filters(server: v33) == ["isFavorite": "true"] && favorites.filters(server: v4) == ["isFavorite": "true"])
        precondition(hidden.filters(server: v33) == ["isHidden": "true"] && all.filters(server: v33).isEmpty)

        precondition(PeopleShow(rawValue: "Hidden") == .hidden && PeopleShow(rawValue: "Favorites") == .favorites)
        print("People filter checks passed.")
    }
}
