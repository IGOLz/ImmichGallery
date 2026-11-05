import Foundation

extension ImmichClient {
    func advancedSearch(_ query: SearchQuery, smartEnabled: Bool, page: SearchPage, progress: (@MainActor @Sendable (Int) -> Void)? = nil) async throws -> SearchResponse.Assets {
        let smart = query.mode == .context && smartEnabled && !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dateSort = smart && query.sort != .automatic
        let body = AdvancedSearchRequest(query, smart: smart, page: dateSort ? .init(page: 1) : page)
        let response: SearchResponse
        do {
            response = try await send("POST", smart ? "search/smart" : "search/metadata", body: body)
        } catch ImmichError.http(404, _) where smart {
            let response: SearchResponse = try await send("POST", "search/metadata", body: AdvancedSearchRequest(query, smart: false, page: page))
            return response.assets
        }
        guard smart, query.sort != .automatic else { return response.assets }
        // Immich smart search has no date order. Sort the complete result set,
        // so dates remain ordered across page boundaries on upstream and Noodle.
        var seen: Set<String> = []
        var items = response.assets.items.filter { seen.insert($0.id).inserted }
        var current = 1
        await progress?(items.count)
        var next = response.assets.nextPage
        while let token = next {
            guard let number = Int(token), number > current else {
                throw ImmichError.http(502, String(localized: "Invalid search pagination"))
            }
            current = number
            try Task.checkCancellation()
            let response: SearchResponse = try await send("POST", "search/smart", body: AdvancedSearchRequest(query, smart: true, page: .init(page: number)))
            items.append(contentsOf: response.assets.items.filter { seen.insert($0.id).inserted })
            await progress?(items.count)
            next = response.assets.nextPage
        }
        try Task.checkCancellation()
        return Self.sortSearchAssets(items, order: query.sort)
    }

    static func sortSearchAssets(_ items: [AssetResponse], order: SearchSort) -> SearchResponse.Assets {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        let dated = items.map { asset in
            (asset: asset, date: (try? fractional.parse(asset.fileCreatedAt)) ?? (try? plain.parse(asset.fileCreatedAt)))
        }
        let sorted = dated.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?) where left != right:
                return order == .oldest ? left < right : left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.asset.id < rhs.asset.id
            }
        }
        return .init(items: sorted.map(\.asset))
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
