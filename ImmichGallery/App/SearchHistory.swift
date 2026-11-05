import Foundation
import Observation

@MainActor @Observable
final class SearchHistory {
    private(set) var entries: [SearchQuery] = []
    private var key = ""

    func load(session: LibrarySession) {
        guard let userID = session.user?.id else { key = ""; entries = []; return }
        key = "searchHistory." + Data((session.client.apiURL.absoluteString + "|" + userID).utf8).base64EncodedString()
        entries = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SearchQuery].self, from: $0) } ?? []
    }

    func remember(_ query: SearchQuery) {
        guard !key.isEmpty, !query.text.isEmpty || !query.chips.isEmpty else { return }
        entries.removeAll {
            var previous = $0
            previous.sort = query.sort
            return previous == query
        }
        entries.insert(query, at: 0)
        entries = Array(entries.prefix(20))
        persist()
    }

    func clear() { entries = []; persist() }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key) }
}
