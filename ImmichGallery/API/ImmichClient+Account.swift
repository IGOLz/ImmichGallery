import Foundation
import CryptoKit

extension ImmichClient {
    func accountPreferences() async throws -> AccountPreferences { try await get("users/me/preferences") }
    func updateAccountPreferences(_ preferences: AccountPreferences) async throws -> AccountPreferences {
        try await send("PUT", "users/me/preferences", body: preferences)
    }
    func updateAccountName(_ name: String) async throws -> User {
        try await send("PUT", "users/me", body: ["name": name])
    }
    func changeAccountPassword(current: String, new: String, invalidateSessions: Bool) async throws {
        struct Body: Encodable { let password: String; let newPassword: String; let invalidateSessions: Bool }
        try await send("POST", "auth/change-password", body: Body(password: current, newPassword: new, invalidateSessions: invalidateSessions))
    }
    func accountKeys() async throws -> [AccountAPIKey] { try await get("api-keys") }
    func createAccountKey(name: String, permissions: [String]) async throws -> AccountAPIKeySecret {
        struct Body: Encodable { let name: String; let permissions: [String] }
        return try await send("POST", "api-keys", body: Body(name: name, permissions: permissions))
    }
    func renameAccountKey(id: String, name: String) async throws {
        try await send("PUT", "api-keys/\(id)", body: ["name": name])
    }
    func deleteAccountKey(_ id: String) async throws { try await send("DELETE", "api-keys/\(id)") }
    func accountDevices() async throws -> [AccountDevice] { try await get("sessions") }
    func deleteAccountDevice(_ id: String) async throws { try await send("DELETE", "sessions/\(id)") }
    func deleteOtherAccountDevices() async throws { try await send("DELETE", "sessions") }
    func accountNotifications() async throws -> [AccountNotification] { try await get("notifications") }
    func readAccountNotifications(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        struct Body: Encodable { let ids: [String]; let readAt: String }
        try await send("PUT", "notifications", body: Body(ids: ids, readAt: Date().ISO8601Format()))
    }
    func deleteAccountNotification(_ id: String) async throws { try await send("DELETE", "notifications/\(id)") }
    func removeAccountPicture() async throws { try await send("DELETE", "users/profile-image") }
    func uploadAccountPicture(_ jpeg: Data) async throws {
        let boundary = UUID().uuidString
        var request = try request("users/profile-image", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        try await data(for: request)
    }

    /// Separate URLCache directories prevent media reuse across servers and users.
    func accountIsolated(userID: String) -> ImmichClient {
        let key = SHA256.hash(data: Data("\(apiURL.absoluteString)|\(userID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let config = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountImages/\(key)", isDirectory: true)
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 4 << 30, directory: directory)
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        return ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: URLSession(configuration: config))
    }
}
