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
        try await get("search/suggestions", query: [
            "type": type, "country": filters.country.isEmpty ? nil : filters.country,
            "state": filters.state.isEmpty ? nil : filters.state,
            "make": filters.make.isEmpty ? nil : filters.make,
            "model": filters.model.isEmpty ? nil : filters.model,
        ])
    }
    func searchCapabilities() async throws -> SearchCapabilities { try await get("server/features") }
    func searchPreferences() async throws -> SearchPreferences { try await get("users/me/preferences") }
    func searchExplore() async throws -> [SearchExploreGroup] { try await get("search/explore") }
}
