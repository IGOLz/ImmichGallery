import Foundation

enum SidebarGroup: String, CaseIterable, Codable {
    case photos, explore, collections, sharing, utilities, myAlbums, sharedAlbums
}

enum SidebarLink: String, CaseIterable, Codable {
    case search, library, favorites, videos
    case map, places, memories, tags, folders
    case albums, people
    case sharedLinks, partners
    case duplicates, largeFiles, geolocation, archive, trash, locked

    var defaultGroup: SidebarGroup {
        switch self {
        case .search, .library, .favorites, .videos: .photos
        case .map, .places, .memories, .tags, .folders: .explore
        case .albums, .people: .collections
        case .sharedLinks, .partners: .sharing
        default: .utilities
        }
    }
}

struct SidebarSection: Codable, Identifiable, Equatable {
    let id: String
    var name: String?
    var hidden = false
    var isCustom: Bool { SidebarGroup(rawValue: id) == nil }
}

struct SidebarLayout {
    private struct Entry: Codable, Equatable {
        let link: String
        let group: String
    }
    private struct Saved: Codable {
        var sections: [SidebarSection]?
        var entries: [Entry]?
        var hiddenLinks: [String]?
        var hiddenDynamicItems: [String]?
    }
    private var entries: [Entry]
    private(set) var sections: [SidebarSection]
    private var hiddenLinks: Set<String>
    private var hiddenDynamicItems: Set<String>

    init(stored: String = "") {
        let data = Data(stored.utf8)
        let saved = try? JSONDecoder().decode(Saved.self, from: data)
        var sectionIDs = Set<String>()
        sections = (saved?.sections ?? []).filter { section in
            let valid = SidebarGroup(rawValue: section.id) != nil ||
                (UUID(uuidString: section.id) != nil && !(section.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
            return valid && sectionIDs.insert(section.id).inserted
        }
        sections += SidebarGroup.allCases.filter { !sectionIDs.contains($0.rawValue) }.map { SidebarSection(id: $0.rawValue) }
        sectionIDs = Set(sections.map(\.id))
        // Migrate the first sidebar ordering format without discarding its order.
        let previous = saved?.entries ?? (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        var seen = Set<String>()
        entries = previous.filter {
            SidebarLink(rawValue: $0.link) != nil && sectionIDs.contains($0.group) && seen.insert($0.link).inserted
        }
        // Keep unavailable features in the layout so changing servers does not lose their position.
        entries += SidebarLink.allCases.filter { !seen.contains($0.rawValue) }.map {
            Entry(link: $0.rawValue, group: $0.defaultGroup.rawValue)
        }
        hiddenLinks = Set(saved?.hiddenLinks ?? []).filter { SidebarLink(rawValue: $0) != nil }
        hiddenDynamicItems = Set(saved?.hiddenDynamicItems ?? [])
    }

    var stored: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = Saved(sections: sections, entries: entries, hiddenLinks: hiddenLinks.sorted(), hiddenDynamicItems: hiddenDynamicItems.sorted())
        return String(decoding: try! encoder.encode(saved), as: UTF8.self)
    }

    func links(in group: SidebarGroup) -> [SidebarLink] { links(in: group.rawValue) }

    func links(in sectionID: String) -> [SidebarLink] {
        entries.filter { $0.group == sectionID }.compactMap { SidebarLink(rawValue: $0.link) }
    }

    func isHidden(_ link: SidebarLink) -> Bool { hiddenLinks.contains(link.rawValue) }
    mutating func setHidden(_ hidden: Bool, link: SidebarLink) {
        if hidden { hiddenLinks.insert(link.rawValue) } else { hiddenLinks.remove(link.rawValue) }
    }
    func isDynamicItemHidden(_ key: String) -> Bool { hiddenDynamicItems.contains(key) }
    mutating func setDynamicItemHidden(_ hidden: Bool, key: String) {
        if hidden { hiddenDynamicItems.insert(key) } else { hiddenDynamicItems.remove(key) }
    }
    mutating func setSectionHidden(_ hidden: Bool, id: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].hidden = hidden
    }

    @discardableResult
    mutating func addSection(named name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let id = UUID().uuidString
        sections.append(SidebarSection(id: id, name: name))
        return id
    }

    mutating func renameSection(id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = sections.firstIndex(where: { $0.id == id }), sections[index].isCustom else { return }
        sections[index].name = name
    }

    mutating func removeSection(id: String) {
        guard sections.contains(where: { $0.id == id && $0.isCustom }) else { return }
        for link in links(in: id) { move(link, to: link.defaultGroup) }
        sections.removeAll { $0.id == id }
    }

    mutating func shiftSection(id: String, by offset: Int) {
        guard let index = sections.firstIndex(where: { $0.id == id }), sections.indices.contains(index + offset) else { return }
        let section = sections.remove(at: index)
        sections.insert(section, at: index + offset)
    }

    @discardableResult
    mutating func move(_ link: SidebarLink, to group: SidebarGroup, relativeTo target: SidebarLink? = nil, after: Bool = false) -> Bool {
        move(link, to: group.rawValue, relativeTo: target, after: after)
    }

    @discardableResult
    mutating func move(_ link: SidebarLink, to sectionID: String, relativeTo target: SidebarLink? = nil, after: Bool = false) -> Bool {
        guard sections.contains(where: { $0.id == sectionID }), target != link else { return false }
        if let target, !links(in: sectionID).contains(target) { return false }
        let previous = entries
        entries.removeAll { $0.link == link.rawValue }
        let index: Int
        if let target, let targetIndex = entries.firstIndex(where: { $0.link == target.rawValue }) {
            index = targetIndex + (after ? 1 : 0)
        } else {
            index = entries.lastIndex(where: { $0.group == sectionID }).map { $0 + 1 } ?? entries.endIndex
        }
        entries.insert(Entry(link: link.rawValue, group: sectionID), at: index)
        return entries != previous
    }
}

/// A row accepts insertion above or below its midpoint, without moving anything during hover.
enum SidebarInsertionEdge {
    case before, after

    init(locationY: Double, rowHeight: Double) {
        self = locationY > rowHeight / 2 ? .after : .before
    }
}
