import Foundation

extension ImmichClient {
    func adminUsers() async throws -> [AdminUser] {
        try await get("admin/users", query: ["withDeleted": "true"])
    }
    func adminSaveUser(id: String?, input: AdminUserInput) async throws {
        try await send(id == nil ? "POST" : "PUT", id.map { "admin/users/\($0)" } ?? "admin/users", body: input)
    }
    func adminDeleteUser(_ id: String, force: Bool) async throws {
        struct Body: Encodable { let force: Bool? }
        try await send("DELETE", "admin/users/\(id)", body: Body(force: force))
    }
    func adminRestoreUser(_ id: String) async throws { try await send("POST", "admin/users/\(id)/restore") }
    func adminLibraries() async throws -> [AdminLibrary] { try await get("libraries") }
    func adminSaveLibrary(id: String?, input: AdminLibraryInput) async throws {
        try await send(id == nil ? "POST" : "PUT", id.map { "libraries/\($0)" } ?? "libraries", body: input)
    }
    func adminValidateLibrary(_ id: String, input: AdminLibraryInput) async throws -> AdminValue {
        struct Body: Encodable { let importPaths: [String]; let exclusionPatterns: [String] }
        return try await send("POST", "libraries/\(id)/validate", body: Body(importPaths: input.importPaths, exclusionPatterns: input.exclusionPatterns))
    }
    func adminScanLibrary(_ id: String) async throws { try await send("POST", "libraries/\(id)/scan") }
    func adminDeleteLibrary(_ id: String) async throws { try await send("DELETE", "libraries/\(id)") }
    func adminQueues() async throws -> [AdminQueue] { try await get("queues") }
    func adminQueueCommand(_ name: String, command: String, force: Bool? = false) async throws {
        switch command {
        case "pause", "resume":
            struct Body: Encodable { let isPaused: Bool }
            try await send("PUT", "queues/\(name)", body: Body(isPaused: command == "pause"))
        case "empty":
            struct Body: Encodable { let failed: Bool }
            try await send("DELETE", "queues/\(name)/jobs", body: Body(failed: false))
        default:
            // v3.3.5 still uses this endpoint for missing/all, as does the web QueuePanel.
            struct Body: Encodable { let command: String; let force: Bool? }
            try await send("PUT", "jobs/\(name)", body: Body(command: command, force: force))
        }
    }
}
