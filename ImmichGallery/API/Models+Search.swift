import Foundation

enum SearchMode: String, Codable, CaseIterable, Identifiable {
    case context = "Context", fileName = "File Name", description = "Description", ocr = "Text in Images"
    var id: Self { self }
}

struct SearchQuery: Codable, Hashable, Sendable {
    var text = ""
    var mode: SearchMode = .context
    var personIDs: Set<String> = []
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

    var chips: [String] {
        var values = [country, state, city, make, model, lensModel, mediaType == "IMAGE" ? "Photos" : mediaType == "VIDEO" ? "Videos" : ""].filter { !$0.isEmpty }
        if !personIDs.isEmpty { values.append("\(personIDs.count) people") }
        if let takenAfter { values.append("After \(takenAfter.formatted(date: .abbreviated, time: .omitted))") }
        if let takenBefore { values.append("Before \(takenBefore.formatted(date: .abbreviated, time: .omitted))") }
        if archived { values.append("Archived") }
        if favorites { values.append("Favorites") }
        if notInAlbum { values.append("Not in an album") }
        if let rating { values.append("\(rating) stars") }
        return values
    }

    var validDates: Bool { takenAfter == nil || takenBefore == nil || takenAfter! <= takenBefore! }
}

/// Both endpoints accept these flat filters in v2 and v3.3.5. The latter deprecates
/// them in favor of SearchFilter, but still uses them in its own web client.
struct AdvancedSearchRequest: Encodable {
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
    var withExif = true
    var order: String?

    init(_ search: SearchQuery, smart: Bool, page: ImmichClient.SearchPage) {
        func value(_ text: String) -> String? { text.isEmpty ? nil : text }
        let text = value(search.text.trimmingCharacters(in: .whitespacesAndNewlines))
        if smart { query = text }
        else {
            switch search.mode {
            case .context, .fileName: originalFileName = text
            case .description: description = text
            case .ocr: ocr = text
            }
            order = "desc"
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

struct SearchCapabilities: Decodable {
    var ocr: Bool?
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
