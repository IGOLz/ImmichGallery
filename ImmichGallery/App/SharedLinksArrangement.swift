import Foundation

// Shared links: the Immich web app's All, Albums and Individual tabs (shared-links/(list)/+layout.svelte),
// plus hiding expired links.

enum SharedLinksFilter: String, CaseIterable, Identifiable {
    // Immich's tab names.
    case all, album, individual
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All Links"
        case .album: "Album Links"
        case .individual: "Individual Shares"
        }
    }
}

struct SharedLinksArrangement {
    var filter = SharedLinksFilter.all
    var hideExpired = false

    var isFiltered: Bool { filter != .all || hideExpired }

    func links(_ links: [SharedLink], now: Date = Date()) -> [SharedLink] {
        links.filter { link in
            switch filter {
            case .all: break
            case .album: guard link.type == "ALBUM" else { return false }
            case .individual: guard link.type == "INDIVIDUAL" else { return false }
            }
            return !hideExpired || !Self.isExpired(link, now: now)
        }
    }

    static func isExpired(_ link: SharedLink, now: Date = Date()) -> Bool {
        link.expiresAt.flatMap(ImmichDate.parse).map { $0 <= now } ?? false
    }
}
