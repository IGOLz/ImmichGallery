import AppIntents
import Foundation

// Configuration of the photo widgets. Compiled into the app too, so it can read which sources
// the installed widgets show (`WidgetInfo.widgetConfigurationIntent`) and prepare only those.

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

struct PhotoWidgetIntent: WidgetConfigurationIntent {
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

    /// Nil while an album, person or place still has to be chosen.
    var feedSource: WidgetFeed.Source? {
        switch source {
        case .featured: .featured
        case .favorites: .favorites
        case .chosen: .chosen
        case .album: album.map { .album($0.id) }
        case .person: person.map { .person($0.id) }
        case .place: place.map { .place($0.id) }
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

private func catalogItems(_ items: KeyPath<WidgetFeed.Catalog, [WidgetFeed.Catalog.Item]>) -> [WidgetFeed.Catalog.Item] {
    WidgetFeed.load()?.catalog?[keyPath: items] ?? []
}

private func matching(_ items: [WidgetFeed.Catalog.Item], _ text: String) -> [WidgetFeed.Catalog.Item] {
    items.filter { $0.name.localizedStandardContains(text) }
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
        matching(catalogItems(\.albums), string).map(WidgetAlbum.init)
    }
    func suggestedEntities() async throws -> [WidgetAlbum] { catalogItems(\.albums).map(WidgetAlbum.init) }
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
        matching(catalogItems(\.places), string).map(WidgetPlace.init)
    }
    func suggestedEntities() async throws -> [WidgetPlace] { catalogItems(\.places).map(WidgetPlace.init) }
}
