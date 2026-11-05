import AppIntents
import Foundation

// Configuration of the photo widgets. Compiled into the app too, so it can read which sources
// the installed widgets show (`WidgetInfo.widgetConfigurationIntent`) and prepare only those.

/// A widget configuration that names a photo source.
protocol PhotoSourceIntent: WidgetConfigurationIntent {
    /// Nil while an album, person or place still has to be chosen and none is known yet.
    var feedSource: WidgetFeed.Source? { get }
}

/// Until the user picks one: the most recently updated album, the person with the most photos and
/// the most recently visited place (the catalog's order), so a new widget shows photos at once.
enum WidgetDefaults {
    static func album(_ chosen: WidgetAlbum?) -> WidgetFeed.Source? {
        (chosen?.id ?? catalogItems(\.albums).first?.id).map(WidgetFeed.Source.album)
    }
    static func person(_ chosen: WidgetPerson?) -> WidgetFeed.Source? {
        (chosen?.id ?? catalogItems(\.people).first?.id).map(WidgetFeed.Source.person)
    }
    static func place(_ chosen: WidgetPlace?) -> WidgetFeed.Source? {
        (chosen?.id ?? catalogItems(\.places).first?.id).map(WidgetFeed.Source.place)
    }
}

struct AlbumWidgetIntent: PhotoSourceIntent {
    static let title: LocalizedStringResource = "Album"
    static let description = IntentDescription("Choose the album to show.")
    static let isDiscoverable = false
    @Parameter(title: "Album") var album: WidgetAlbum?
    var feedSource: WidgetFeed.Source? { WidgetDefaults.album(album) }
}

struct PersonWidgetIntent: PhotoSourceIntent {
    static let title: LocalizedStringResource = "Person"
    static let description = IntentDescription("Choose the person or pet to show.")
    static let isDiscoverable = false
    @Parameter(title: "Person") var person: WidgetPerson?
    var feedSource: WidgetFeed.Source? { WidgetDefaults.person(person) }
}

struct PlaceWidgetIntent: PhotoSourceIntent {
    static let title: LocalizedStringResource = "Place"
    static let description = IntentDescription("Choose the place to show.")
    static let isDiscoverable = false
    @Parameter(title: "Place") var place: WidgetPlace?
    var feedSource: WidgetFeed.Source? { WidgetDefaults.place(place) }
}

enum WidgetPhotoSource: String, AppEnum {
    case featured, favorites, album, person, place, chosen

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Photos"
    static let caseDisplayRepresentations: [WidgetPhotoSource: DisplayRepresentation] = [
        .featured: "Featured",
        .favorites: "Favorites",
        .album: "Album",
        .person: "Person",
        .place: "Place",
        .chosen: "Chosen Photos",
    ]
}

/// The mosaic's settings: any source.
struct PhotoWidgetIntent: PhotoSourceIntent {
    static let title: LocalizedStringResource = "Photos"
    static let description = IntentDescription("Choose which photos the widget shows.")
    static let isDiscoverable = false

    @Parameter(title: "Show", default: .featured) var source: WidgetPhotoSource
    @Parameter(title: "Album") var album: WidgetAlbum?
    @Parameter(title: "Person") var person: WidgetPerson?
    @Parameter(title: "Place") var place: WidgetPlace?

    static var parameterSummary: some ParameterSummary {
        Switch(\.$source) {
            Case(.album) { Summary("Show \(\.$source): \(\.$album)") }
            Case(.person) { Summary("Show \(\.$source): \(\.$person)") }
            Case(.place) { Summary("Show \(\.$source): \(\.$place)") }
            DefaultCase { Summary("Show \(\.$source)") }
        }
    }

    var feedSource: WidgetFeed.Source? {
        switch source {
        case .featured: .featured
        case .favorites: .favorites
        case .chosen: .chosen
        case .album: WidgetDefaults.album(album)
        case .person: WidgetDefaults.person(person)
        case .place: WidgetDefaults.place(place)
        }
    }
}

/// The widget's "Next Photo" button. Runs in the widget extension; WidgetKit then reloads it.
struct NextPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Photo"
    static let isDiscoverable = false

    @Parameter(title: "Photos") var pool: String

    init() {}
    init(pool: String) { self.pool = pool }

    func perform() async throws -> some IntentResult {
        WidgetFeed.advance(pool)
        return .result()
    }
}

// MARK: Albums, people and places, from the catalog the app saved

func catalogItems(_ items: KeyPath<WidgetFeed.Catalog, [WidgetFeed.Catalog.Item]>) -> [WidgetFeed.Catalog.Item] {
    WidgetFeed.load()?.catalog?[keyPath: items] ?? []
}

private func matching(_ items: [WidgetFeed.Catalog.Item], _ text: String) -> [WidgetFeed.Catalog.Item] {
    items.filter { $0.name.localizedStandardContains(text) }
}

/// Pickers list albums and places by name; the catalog keeps them most recent first.
private func byName(_ items: [WidgetFeed.Catalog.Item]) -> [WidgetFeed.Catalog.Item] {
    items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

struct WidgetAlbum: AppEntity {
    let id: String
    let name: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static let defaultQuery = WidgetAlbumQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ item: WidgetFeed.Catalog.Item) { id = item.id; name = item.name }
}

struct WidgetAlbumQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAlbum] {
        catalogItems(\.albums).filter { identifiers.contains($0.id) }.map(WidgetAlbum.init)
    }
    func entities(matching string: String) async throws -> [WidgetAlbum] {
        byName(matching(catalogItems(\.albums), string)).map(WidgetAlbum.init)
    }
    func suggestedEntities() async throws -> [WidgetAlbum] { byName(catalogItems(\.albums)).map(WidgetAlbum.init) }
}

struct WidgetPerson: AppEntity {
    let id: String
    let name: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = WidgetPersonQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ item: WidgetFeed.Catalog.Item) { id = item.id; name = item.name }
}

struct WidgetPersonQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetPerson] {
        catalogItems(\.people).filter { identifiers.contains($0.id) }.map(WidgetPerson.init)
    }
    func entities(matching string: String) async throws -> [WidgetPerson] {
        matching(catalogItems(\.people), string).map(WidgetPerson.init)
    }
    func suggestedEntities() async throws -> [WidgetPerson] { catalogItems(\.people).map(WidgetPerson.init) }
}

struct WidgetPlace: AppEntity {
    let id: String
    let name: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static let defaultQuery = WidgetPlaceQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ item: WidgetFeed.Catalog.Item) { id = item.id; name = item.name }
}

struct WidgetPlaceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetPlace] {
        catalogItems(\.places).filter { identifiers.contains($0.id) }.map(WidgetPlace.init)
    }
    func entities(matching string: String) async throws -> [WidgetPlace] {
        byName(matching(catalogItems(\.places), string)).map(WidgetPlace.init)
    }
    func suggestedEntities() async throws -> [WidgetPlace] { byName(catalogItems(\.places)).map(WidgetPlace.init) }
}
