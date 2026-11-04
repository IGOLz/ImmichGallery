import Foundation

extension ImmichClient {
    func advancedSearch(_ query: SearchQuery, smartEnabled: Bool, page: SearchPage) async throws -> SearchResponse.Assets {
        let smart = query.mode == .context && smartEnabled && !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = AdvancedSearchRequest(query, smart: smart, page: page)
        do {
            let response: SearchResponse = try await send("POST", smart ? "search/smart" : "search/metadata", body: body)
            return response.assets
        } catch ImmichError.http(404, _) where smart {
            let response: SearchResponse = try await send("POST", "search/metadata", body: AdvancedSearchRequest(query, smart: false, page: page))
            return response.assets
        }
    }

    func searchSuggestions(_ type: String, filters: SearchQuery) async throws -> [String] {
        try await get("search/suggestions", query: Self.searchSuggestionParameters(type, filters: filters))
    }

    static func searchSuggestionParameters(_ type: String, filters: SearchQuery) -> [String: String?] {
        func value(_ text: String) -> String? { text.isEmpty ? nil : text }
        return [
            "type": type,
            "country": type == "state" || type == "city" ? value(filters.country) : nil,
            "state": type == "city" ? value(filters.state) : nil,
            "make": type == "camera-model" || type == "camera-lens-model" ? value(filters.make) : nil,
            "model": type == "camera-lens-model" ? value(filters.model) : nil,
        ]
    }
    func searchPreferences() async throws -> SearchPreferences { try await get("users/me/preferences") }
    func searchExplore() async throws -> [SearchExploreGroup] { try await get("search/explore") }
}
