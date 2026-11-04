import Foundation

extension ImmichClient {
    func peoplePage(page: Int, withHidden: Bool, name: String? = nil) async throws -> PeopleResponse {
        try await get("people", query: ["page": String(page), "size": "100", "withHidden": String(withHidden), "name": name])
    }
    func person(_ id: String) async throws -> Person { try await get("people/\(id)") }
    func personStatistics(_ id: String) async throws -> PeopleStatistics { try await get("people/\(id)/statistics") }
    func editPerson(_ id: String, _ edit: PersonEdit) async throws -> Person {
        try await send("PUT", "people/\(id)", body: edit)
    }
    func createPerson(name: String) async throws -> Person {
        try await send("POST", "people", body: PersonEdit(name: name))
    }
    func mergePeople(into id: String, ids: [String]) async throws {
        struct Body: Encodable { let ids: [String] }
        let results: [PeopleOperationResult] = try await send("POST", "people/\(id)/merge", body: Body(ids: ids))
        if let failed = results.first(where: { !$0.success }) {
            throw ImmichError.http(400, failed.errorMessage ?? failed.error ?? "Couldn't merge people.")
        }
    }
    func faces(assetID: String) async throws -> [PeopleFace] { try await get("faces", query: ["id": assetID]) }
    func reassignFace(_ faceID: String, to personID: String) async throws -> Person {
        struct Body: Encodable { let id: String }
        return try await send("PUT", "faces/\(personID)", body: Body(id: faceID))
    }
    func removeFace(_ id: String) async throws {
        struct Body: Encodable { let force: Bool }
        try await send("DELETE", "faces/\(id)", body: Body(force: false))
    }
}
