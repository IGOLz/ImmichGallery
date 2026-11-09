import Foundation

/// Timeline pages: view options become timeline API filters and survive in the page's saved settings.
@main struct TimelineArrangementChecks {
    static func main() throws {
        let library = TimelineQuery(withPartners: true)
        let v2 = ServerVersion(major: 2, minor: 7, patch: 5), v3 = ServerVersion(major: 3, minor: 0, patch: 0)
        precondition(!TimelineArrangement.supportsDateAdded(v2) && TimelineArrangement.supportsDateAdded(v3))
        precondition(!TimelineArrangement.supportsDateAdded(nil))

        // The defaults ask the server for exactly what the page asked for before.
        let plain = TimelineArrangement().applied(to: library, dateAdded: true)
        precondition(plain == library)
        precondition(plain.parameters["order"] == .some(nil) && plain.parameters["orderBy"] == .some(nil))

        // Favorites drop partners' photos, which the server refuses together with a favorites filter.
        let favorites = TimelineArrangement(show: .favorites).applied(to: library, dateAdded: true)
        precondition(favorites.isFavorite == true && favorites.withPartners == nil)

        // Oldest first and Date Added, the latter only on servers that support it.
        let added = TimelineArrangement(sortBy: .dateAdded, order: .oldestFirst)
        precondition(added.applied(to: library, dateAdded: true).parameters["orderBy"] == "createdAt")
        precondition(added.applied(to: library, dateAdded: true).parameters["order"] == "asc")
        precondition(added.applied(to: library, dateAdded: false).orderBy == nil)
        precondition(added.applied(to: library, dateAdded: false).order == "asc")

        // Sections: Date Taken uses the photo's own clock, Date Added the upload time in UTC.
        let taken = "2026-01-01T00:30:00.000Z", uploaded = "2025-12-31T23:30:00.000Z"
        precondition(TimelineArrangement().month(localDateTime: taken, createdAt: uploaded, dateAdded: true) == "2026-01")
        precondition(added.month(localDateTime: taken, createdAt: uploaded, dateAdded: true) == "2025-12")
        precondition(added.month(localDateTime: taken, createdAt: uploaded, dateAdded: false) == "2026-01")
        precondition(added.month(localDateTime: taken, createdAt: nil, dateAdded: true) == nil)

        // Saved settings, per page, with the API's names.
        let defaults = UserDefaults(suiteName: "TimelineArrangementChecks")!
        defaults.removePersistentDomain(forName: "TimelineArrangementChecks")
        precondition(TimelineArrangement(page: .library, defaults: defaults) == TimelineArrangement())
        defaults.set("Favorites", forKey: "timeline.library.show")
        defaults.set("createdAt", forKey: "timeline.library.sortBy")
        defaults.set("asc", forKey: "timeline.library.order")
        precondition(TimelineArrangement(page: .library, defaults: defaults) == TimelineArrangement(show: .favorites, sortBy: .dateAdded, order: .oldestFirst))
        precondition(TimelineArrangement(page: .archive, defaults: defaults) == TimelineArrangement())
        // Pages without a favorites filter ignore a saved one.
        defaults.set("Favorites", forKey: "timeline.favorites.show")
        defaults.set("Favorites", forKey: "timeline.partner.show")
        precondition(!TimelineArrangement(page: .favorites, defaults: defaults).isFiltered)
        precondition(!TimelineArrangement(page: .partner, defaults: defaults).isFiltered)
        defaults.set("Nonsense", forKey: "timeline.tag.order")
        precondition(TimelineArrangement(page: .tag, defaults: defaults).order == .newestFirst)
        defaults.removePersistentDomain(forName: "TimelineArrangementChecks")
        print("Timeline view options checks passed.")
    }
}
