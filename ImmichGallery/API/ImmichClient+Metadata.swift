import Foundation

extension ImmichClient {
    func updateMetadata(_ update: MetadataUpdate) async throws {
        try await send("PUT", "assets", body: update)
    }

    func metadataPreferences() async throws -> MetadataPreferences {
        try await get("users/me/preferences")
    }

    func metadataEdits(_ id: String) async throws -> MetadataEdits {
        try await get("assets/\(id)/edits")
    }

    func saveMetadataEdits(_ id: String, edits: [MetadataEdit]) async throws {
        if edits.isEmpty { try await send("DELETE", "assets/\(id)/edits") }
        else { try await send("PUT", "assets/\(id)/edits", body: MetadataEdits(edits: edits)) }
    }
}
