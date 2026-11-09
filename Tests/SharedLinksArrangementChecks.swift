import Foundation

/// Shared links: the Immich web app's All, Albums and Individual tabs, and hiding expired links.
@main struct SharedLinksArrangementChecks {
    static func main() throws {
        let json = #"""
        [
          {"id":"a", "key":"k1", "type":"ALBUM", "allowDownload":true, "allowUpload":false, "showMetadata":true, "assets":[]},
          {"id":"b", "key":"k2", "type":"INDIVIDUAL", "allowDownload":true, "allowUpload":false, "showMetadata":true, "assets":[],
           "expiresAt":"2026-01-01T00:00:00.000Z"},
          {"id":"c", "key":"k3", "type":"ALBUM", "allowDownload":true, "allowUpload":false, "showMetadata":true, "assets":[],
           "expiresAt":"2027-01-01T00:00:00.000Z"}
        ]
        """#
        let links = try JSONDecoder().decode([SharedLink].self, from: Data(json.utf8))
        let now = ImmichDate.parse("2026-06-01T00:00:00.000Z")!
        let ids = { (arrangement: SharedLinksArrangement) in arrangement.links(links, now: now).map(\.id) }

        precondition(ids(SharedLinksArrangement()) == ["a", "b", "c"])
        precondition(!SharedLinksArrangement().isFiltered)
        precondition(ids(SharedLinksArrangement(filter: .album)) == ["a", "c"])
        precondition(ids(SharedLinksArrangement(filter: .individual)) == ["b"])
        precondition(ids(SharedLinksArrangement(hideExpired: true)) == ["a", "c"])
        precondition(ids(SharedLinksArrangement(filter: .individual, hideExpired: true)).isEmpty)
        precondition(SharedLinksArrangement(hideExpired: true).isFiltered)

        // Settings saved by the app use Immich's tab names.
        precondition(SharedLinksFilter(rawValue: "album") == .album && SharedLinksFilter(rawValue: "individual") == .individual)
        print("Shared link filter checks passed.")
    }
}
