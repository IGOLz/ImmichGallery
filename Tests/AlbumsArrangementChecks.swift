import Foundation

/// Albums: grouping and sorting follow the Immich web app's albums page.
@main struct AlbumsArrangementChecks {
    static func main() throws {
        let json = #"""
        [
          {"id":"a", "albumName":"beach", "assetCount":5, "shared":false, "createdAt":"2020-01-01T00:00:00.000Z",
           "updatedAt":"2026-01-03T00:00:00.000Z", "startDate":"2023-06-01T00:00:00.000Z", "endDate":"2025-01-01T00:00:00.000Z",
           "albumUsers":[{"role":"owner", "user":{"id":"me", "name":"Me", "email":"me@example.com"}}]},
          {"id":"b", "albumName":"Alps", "assetCount":9, "shared":true, "createdAt":"2021-01-01T00:00:00.000Z",
           "updatedAt":"2026-01-01T00:00:00.000Z", "startDate":"2024-12-01T00:00:00.000Z", "endDate":"2024-12-31T00:00:00.000Z",
           "albumUsers":[{"role":"owner", "user":{"id":"me", "name":"Me", "email":"me@example.com"}},
                         {"role":"editor", "user":{"id":"zoe", "name":"Zoe", "email":"zoe@example.com"}}]},
          {"id":"c", "albumName":"Cats", "assetCount":2, "shared":true, "createdAt":"2022-01-01T00:00:00.000Z",
           "updatedAt":"2026-01-02T00:00:00.000Z", "startDate":"2022-03-01T00:00:00.000Z", "endDate":"2025-07-01T00:00:00.000Z",
           "albumUsers":[{"role":"owner", "user":{"id":"zoe", "name":"Zoe", "email":"zoe@example.com"}},
                         {"role":"viewer", "user":{"id":"me", "name":"Me", "email":"me@example.com"}}]},
          {"id":"d", "albumName":"Empty", "assetCount":0, "shared":true, "createdAt":"2023-01-01T00:00:00.000Z",
           "updatedAt":"2026-01-04T00:00:00.000Z",
           "owner":{"id":"adam", "name":"Adam", "email":"adam@example.com"}}
        ]
        """#
        let albums = try JSONDecoder().decode([Album].self, from: Data(json.utf8))
        let ids = { (albums: [Album]) in albums.map(\.id) }

        // Immich's defaults: years from the newest photo, newest year first, albums without photos last.
        let defaults = AlbumsArrangement()
        let years = defaults.groups(albums, userID: "me")
        precondition(years.map(\.header) == [.year(2025), .year(2024), .unknownYear])
        precondition(years.map { ids($0.albums) } == [["c", "a"], ["b"], ["d"]])

        // Ascending years still keep albums without photos last; sorting by the oldest photo uses its year.
        var oldest = AlbumsArrangement(groupOrder: .ascending, sortBy: .oldestPhoto, sortOrder: .ascending)
        precondition(oldest.groups(albums, userID: "me").map(\.header) == [.year(2022), .year(2023), .year(2024), .unknownYear])
        oldest.groupBy = .none
        precondition(ids(oldest.groups(albums, userID: "me")[0].albums) == ["c", "a", "b", "d"])

        // Album dates say nothing about photo years, so Immich drops year groups for them.
        for sort in [AlbumsSortBy.dateCreated, .dateModified] {
            let arrangement = AlbumsArrangement(sortBy: sort)
            precondition(!arrangement.allows(.year) && arrangement.effectiveGroupBy == .none)
            precondition(arrangement.groups(albums, userID: "me").map(\.header) == [nil])
        }
        precondition(ids(AlbumsArrangement(groupBy: .none, sortBy: .dateCreated).sorted(albums)) == ["d", "c", "b", "a"])
        precondition(ids(AlbumsArrangement(groupBy: .none, sortBy: .dateModified).sorted(albums)) == ["d", "a", "c", "b"])

        // Owners: your albums first in ascending order, then other owners by name; reversed when descending.
        let owners = AlbumsArrangement(groupBy: .owner, groupOrder: .ascending, sortBy: .title, sortOrder: .ascending)
        precondition(owners.groups(albums, userID: "me").map(\.header) == [.mine, .owner("Adam"), .owner("Zoe")])
        precondition(ids(owners.groups(albums, userID: "me")[0].albums) == ["b", "a"])
        var descending = owners
        descending.groupOrder = .descending
        precondition(descending.groups(albums, userID: "me").map(\.header) == [.owner("Zoe"), .owner("Adam"), .mine])

        // Titles ignore case; item count; filters.
        precondition(ids(owners.sorted(albums)) == ["b", "a", "c", "d"])
        precondition(ids(AlbumsArrangement(sortBy: .itemCount, sortOrder: .descending).sorted(albums)) == ["b", "a", "c", "d"])
        let none = AlbumsArrangement(groupBy: .none, sortBy: .title, sortOrder: .ascending)
        var filtered = none
        filtered.filter = .owned
        precondition(ids(filtered.groups(albums, userID: "me")[0].albums) == ["b", "a"])
        filtered.filter = .shared
        precondition(ids(filtered.groups(albums, userID: "me")[0].albums) == ["b", "c", "d"])
        precondition(filtered.groups([], userID: "me").isEmpty)

        // Sidebar sections list the first albums in the chosen order, or all of them without a limit.
        precondition(ids(AlbumsArrangement.sidebar(albums, sortBy: .dateModified, limit: 2)) == ["d", "a"])
        precondition(ids(AlbumsArrangement.sidebar(albums, sortBy: .mostRecentPhoto, limit: 3)) == ["c", "a", "b"])
        precondition(ids(AlbumsArrangement.sidebar(albums, sortBy: .title, limit: nil)) == ["b", "a", "c", "d"])
        precondition(AlbumsArrangement.sidebar(albums, sortBy: .title, limit: 10).count == albums.count)

        // Settings saved by the app use Immich's names.
        precondition(AlbumsGroupBy(rawValue: "Year") == .year && AlbumsSortBy(rawValue: "MostRecentPhoto") == .mostRecentPhoto)
        precondition(AlbumsSortOrder(rawValue: "desc") == .descending && AlbumsFilter(rawValue: "Owned") == .owned)
        print("Album grouping and sorting checks passed.")
    }
}
