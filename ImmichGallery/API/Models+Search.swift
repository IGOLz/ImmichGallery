import Foundation

enum SearchMode: String, Codable, CaseIterable, Identifiable {
    case context = "Context", fileName = "File Name", description = "Description", ocr = "Text in Images"
    var title: LocalizedStringResource {
        switch self {
        case .context: "Context"
        case .fileName: "File Name"
        case .description: "Description"
        case .ocr: "Text in Images"
        }
    }
    var id: Self { self }
}

enum SearchSort: String, Codable, CaseIterable, Identifiable {
    case automatic, newest, oldest
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Default Order"
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        }
    }
}

struct SearchQuery: Codable, Hashable, Sendable {
    var text = ""
    var mode: SearchMode = .context
    var sort: SearchSort = .automatic
    var personIDs: Set<String> = []
    var personNames: [String: String] = [:]
    var country = ""
    var state = ""
    var city = ""
    var make = ""
    var model = ""
    var lensModel = ""
    var takenAfter: Date?
    var takenBefore: Date?
    var mediaType = ""
    var archived = false
    var favorites = false
    var notInAlbum = false
    var rating: Int?

    enum Filter: String, Identifiable {
        case country, state, city, make, model, lensModel, mediaType, people
        case takenAfter, takenBefore, archived, favorites, notInAlbum, rating
        var id: Self { self }
    }

    var filterChips: [(id: Filter, title: String)] {
        var values: [(id: Filter, title: String)] = []
        for (field, value) in [(Filter.country, country), (.state, state), (.city, city),
                               (.make, make), (.model, model), (.lensModel, lensModel),
                               (.mediaType, mediaType == "IMAGE" ? "Photos" : mediaType == "VIDEO" ? "Videos" : "")] where !value.isEmpty {
            values.append((field, value))
        }
        if !personIDs.isEmpty {
            values.append((.people, personIDs.sorted().map { personNames[$0] ?? "Unnamed Person" }.joined(separator: ", ")))
        }
        if let takenAfter { values.append((.takenAfter, "After \(takenAfter.formatted(date: .abbreviated, time: .omitted))")) }
        if let takenBefore { values.append((.takenBefore, "Before \(takenBefore.formatted(date: .abbreviated, time: .omitted))")) }
        if archived { values.append((.archived, "Archived")) }
        if favorites { values.append((.favorites, "Favorites")) }
        if notInAlbum { values.append((.notInAlbum, "Not in an album")) }
        if let rating { values.append((.rating, "\(rating) stars")) }
        return values
    }

    var chips: [String] { filterChips.map(\.title) }

    mutating func remove(_ filter: Filter) {
        switch filter {
        case .country: country = ""
        case .state: state = ""
        case .city: city = ""
        case .make: make = ""
        case .model: model = ""
        case .lensModel: lensModel = ""
        case .mediaType: mediaType = ""
        case .people: personIDs = []; personNames = [:]
        case .takenAfter: takenAfter = nil
        case .takenBefore: takenBefore = nil
        case .archived: archived = false
        case .favorites: favorites = false
        case .notInAlbum: notInAlbum = false
        case .rating: rating = nil
        }
    }

    mutating func clampMode(smartEnabled: Bool, ocrEnabled: Bool) {
        if (mode == .context && !smartEnabled) || (mode == .ocr && !ocrEnabled) { mode = .fileName }
    }

    var validDates: Bool {
        guard let takenAfter, let takenBefore else { return true }
        return Calendar.current.startOfDay(for: takenAfter) <= Calendar.current.startOfDay(for: takenBefore)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case text, mode, sort, personIDs, personNames, country, state, city, make, model, lensModel
        case takenAfter, takenBefore, mediaType, archived, favorites, notInAlbum, rating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        mode = try c.decodeIfPresent(SearchMode.self, forKey: .mode) ?? .context
        sort = try c.decodeIfPresent(SearchSort.self, forKey: .sort) ?? .automatic
        personIDs = try c.decodeIfPresent(Set<String>.self, forKey: .personIDs) ?? []
        personNames = try c.decodeIfPresent([String: String].self, forKey: .personNames) ?? [:]
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        make = try c.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        lensModel = try c.decodeIfPresent(String.self, forKey: .lensModel) ?? ""
        takenAfter = try c.decodeIfPresent(Date.self, forKey: .takenAfter)
        takenBefore = try c.decodeIfPresent(Date.self, forKey: .takenBefore)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        favorites = try c.decodeIfPresent(Bool.self, forKey: .favorites) ?? false
        notInAlbum = try c.decodeIfPresent(Bool.self, forKey: .notInAlbum) ?? false
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
    }

}

/// Both endpoints accept these flat filters in v2 and v3.3.5. The latter deprecates
/// them in favor of SearchFilter, but still uses them in its own web client.
struct AdvancedSearchRequest: Encodable {
    static let smartDateResultLimit = 500

    var query: String?
    var originalFileName: String?
    var description: String?
    var ocr: String?
    var personIds: [String]?
    var country: String?
    var state: String?
    var city: String?
    var make: String?
    var model: String?
    var lensModel: String?
    var takenAfter: String?
    var takenBefore: String?
    var type: String?
    var visibility: String?
    var isFavorite: Bool?
    var isNotInAlbum: Bool?
    var rating: Int?
    var page: Int?
    var cursor: String?
    var size = 100
    var order: String?

    init(_ search: SearchQuery, smart: Bool, page: ImmichClient.SearchPage) {
        func value(_ text: String) -> String? { text.isEmpty ? nil : text }
        let text = value(search.text.trimmingCharacters(in: .whitespacesAndNewlines))
        if smart {
            query = text
            if search.sort != .automatic { size = Self.smartDateResultLimit }
        }
        else {
            switch search.mode {
            case .context, .fileName: originalFileName = text
            case .description: description = text
            case .ocr: ocr = text
            }
            order = search.sort == .oldest ? "asc" : "desc"
        }
        personIds = search.personIDs.isEmpty ? nil : search.personIDs.sorted()
        country = value(search.country); state = value(search.state); city = value(search.city)
        make = value(search.make); model = value(search.model); lensModel = value(search.lensModel)
        // Match the web's inclusive calendar-day range in local wall-clock time.
        let calendar = Calendar.current
        takenAfter = search.takenAfter.map { calendar.startOfDay(for: $0).ISO8601Format() }
        takenBefore = search.takenBefore.map {
            (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))!.addingTimeInterval(-0.001)).ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
        }
        type = value(search.mediaType)
        visibility = search.archived ? "archive" : nil
        isFavorite = search.favorites ? true : nil
        isNotInAlbum = search.notInAlbum ? true : nil
        rating = search.rating
        self.page = page.page
        cursor = smart ? nil : page.cursor
    }
}

struct SearchPreferences: Decodable {
    struct Ratings: Decodable { var enabled: Bool }
    var ratings: Ratings?
}
struct SearchExploreGroup: Decodable {
    struct Item: Decodable { var value: String; var data: AssetResponse }
    var fieldName: String
    var items: [Item]
}
