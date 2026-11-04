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

    private static let accountSessions = AccountSessionRegistry()

    static func accountCacheDirectory(apiURL: URL, userID: String) -> URL {
        let key = SHA256.hash(data: Data("\(apiURL.absoluteString)|\(userID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountImages/\(key)", isDirectory: true)
    }

    static func removeAccountCache(apiURL: URL, userID: String) throws {
        let directory = accountCacheDirectory(apiURL: apiURL, userID: userID)
        accountSessions.lock.lock()
        defer { accountSessions.lock.unlock() }
        if let session = accountSessions.sessions.removeValue(forKey: directory.path) {
            session.invalidateAndCancel()
            session.configuration.urlCache?.removeAllCachedResponses()
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// One URLSession/URLCache per directory, including after switching back to an account.
    func accountIsolated(userID: String) -> ImmichClient {
        let directory = Self.accountCacheDirectory(apiURL: apiURL, userID: userID)
        Self.accountSessions.lock.lock()
        defer { Self.accountSessions.lock.unlock() }
        let session: URLSession
        if let existing = Self.accountSessions.sessions[directory.path] { session = existing }
        else {
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 4 << 30, directory: directory)
            config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            config.httpMaximumConnectionsPerHost = 8
            config.timeoutIntervalForRequest = 30
            session = URLSession(configuration: config)
            Self.accountSessions.sessions[directory.path] = session
        }
        return ImmichClient(serverURL: serverURL, apiURL: apiURL, credential: credential, session: session)
    }
}

private final class AccountSessionRegistry: @unchecked Sendable {
    let lock = NSLock()
    var sessions: [String: URLSession] = [:]
}
