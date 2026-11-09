import Foundation

/// Collapsed groups on the albums and places pages, saved per grouping like Immich's `collapsedGroups`
/// ({"Year": ["year-2024"]}). A `nil` grouping is no grouping, where nothing collapses.
struct CollapsedGroups {
    private var groups: [String: [String]]

    init(stored: String) {
        groups = (try? JSONDecoder().decode([String: [String]].self, from: Data(stored.utf8))) ?? [:]
    }

    var stored: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: (try? encoder.encode(groups)) ?? Data("{}".utf8), as: UTF8.self)
    }

    func isCollapsed(_ id: String, in grouping: String?) -> Bool {
        grouping.map { groups[$0, default: []].contains(id) } ?? false
    }

    mutating func toggle(_ id: String, in grouping: String?) {
        guard let grouping else { return }
        var ids = groups[grouping, default: []]
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) } else { ids.append(id) }
        groups[grouping] = ids.isEmpty ? nil : ids
    }

    mutating func set(_ ids: [String], in grouping: String?) {
        guard let grouping else { return }
        groups[grouping] = ids.isEmpty ? nil : ids
    }
}
