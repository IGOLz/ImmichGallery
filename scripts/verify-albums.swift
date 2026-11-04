// Compile with API/Models.swift and API/Models+Albums.swift, then pass a directory
// containing JSON responses captured from an Immich server. No network or mutations.
import Foundation

@main
struct VerifyAlbums {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        func decode<T: Decodable>(_ name: String, _: T.Type) throws -> T {
            try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        }
        let albums = try decode("albums", [Album].self)
        _ = try decode("shared", [Album].self)
        _ = try decode("users", [User].self)
        let created = try decode("created", AlbumDetails.self)
        let updated = try decode("updated", AlbumDetails.self)
        assert(created.assetCount == 0)
        assert(updated.order == "asc" && updated.description == "Temporary API check")
        assert(updated.isOwner(updated.albumOwner?.id))
        assert(!updated.canEdit(nil))
        _ = try decode("cover", AlbumDetails.self)
        let added = try decode("added", [AlbumAssetResult].self)
        let removed = try decode("removed", [AlbumAssetResult].self)
        assert(added.allSatisfy(\.success) && removed.allSatisfy(\.success))
        _ = try decode("activities", [AlbumActivity].self)
        let activity = try decode("activity", AlbumActivity.self)
        assert(activity.type == "comment" && activity.assetId == nil)
        let counts = try decode("statistics", AlbumActivityStatistics.self)
        assert(counts.comments == 1)
        _ = try decode("shared-detail", AlbumDetails.self)
        _ = try decode("shared-activities", [AlbumActivity].self)
        _ = try decode("shared-statistics", AlbumActivityStatistics.self)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AlbumUpdate(description: ""))) as! [String: Any]
        assert(json["description"] is NSNull && json["order"] == nil)
        let legacy = Data("""
        {"id":"legacy", "albumName":"Legacy", "assetCount":0, "shared":true,
         "owner":{"id":"owner", "name":"Owner", "email":"owner@example.com"},
         "albumUsers":[{"role":"viewer","user":{"id":"viewer", "name":"Viewer", "email":"viewer@example.com"}}]}
        """.utf8)
        let v2 = try JSONDecoder().decode(AlbumDetails.self, from: legacy)
        assert(v2.isOwner("owner") && !v2.canEdit("viewer") && !v2.isOwner(nil))
        print("PASS: \(albums.count) live albums, details, users, bulk results, activity, nullable update encoding, v2 owner and viewer permissions")
    }
}
