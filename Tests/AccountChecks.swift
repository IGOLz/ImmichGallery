import Foundation

/// Run with the command documented in Docs/Account.md. No writes to a server or Keychain.
@main
struct AccountChecks {
    static func main() async throws {
        let directory = CommandLine.arguments.dropFirst().first ?? "build/AccountChecks"
        let decoder = JSONDecoder()
        func fixture<T: Decodable>(_ name: String, _: T.Type) throws -> T {
            try decoder.decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: directory + "/" + name + ".json")))
        }
        let user = try fixture("user", User.self)
        precondition(!user.id.isEmpty && !user.email.isEmpty)
        let preferences = try fixture("preferences", AccountPreferences.self)
        precondition(preferences.download?.archiveSize != nil)
        let roundtrip = try decoder.decode(AccountPreferences.self, from: JSONEncoder().encode(preferences))
        precondition(roundtrip.people?.enabled == preferences.people?.enabled)
        _ = try fixture("keys", [AccountAPIKey].self)
        let created = try fixture("created-key", AccountAPIKeySecret.self)
        precondition(!created.secret.isEmpty && (created.id != nil || created.apiKey != nil))
        let devices = try fixture("sessions", [AccountDevice].self)
        precondition(devices.filter(\.current).count == 1)
        _ = try fixture("notifications", [AccountNotification].self)
        let empty = try decoder.decode(AccountPreferences.self, from: Data("{}".utf8))
        precondition(empty.memories == nil && empty.download == nil)
        let notification = try decoder.decode(AccountNotification.self, from: Data("""
        {"id":"test","title":"Test","level":"info","createdAt":"2026-01-01T00:00:00Z"}
        """.utf8))
        precondition(notification.readAt == nil && notification.description == nil)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountTestProtocol.self]
        let client = ImmichClient(serverURL: URL(string: "https://example.com")!,
                                  apiURL: URL(string: "https://example.com/api")!,
                                  credential: .accessToken("test"), session: URLSession(configuration: config))
        try await client.changeAccountPassword(current: "current", new: "new-password", invalidateSessions: true)
        let password = AccountTestProtocol.lastRequest!
        precondition(password.httpMethod == "POST" && password.url!.path == "/api/auth/change-password")
        let passwordBody = try JSONSerialization.jsonObject(with: AccountTestProtocol.lastBody!) as! [String: Any]
        precondition(passwordBody["invalidateSessions"] as? Bool == true && passwordBody["password"] as? String == "current")
        try await client.readAccountNotifications(["test"])
        precondition(AccountTestProtocol.lastRequest!.httpMethod == "PUT")
        let readBody = try JSONSerialization.jsonObject(with: AccountTestProtocol.lastBody!) as! [String: Any]
        precondition(readBody["readAt"] is String && readBody["ids"] as? [String] == ["test"])
        try await client.uploadAccountPicture(Data([1, 2, 3]))
        let multipart = AccountTestProtocol.lastRequest!
        precondition(multipart.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        precondition(AccountTestProtocol.lastBody!.range(of: Data("name=\"file\"".utf8)) != nil)
        precondition(multipart.value(forHTTPHeaderField: "Authorization") == "Bearer test")
        let testID = "account-check-" + UUID().uuidString
        let one = client.accountIsolated(userID: testID)
        defer { try? ImmichClient.removeAccountCache(apiURL: client.apiURL, userID: testID) }
        let again = client.accountIsolated(userID: testID)
        precondition(one.session === again.session)
        let cacheDirectory = ImmichClient.accountCacheDirectory(apiURL: client.apiURL, userID: testID)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data([1]).write(to: cacheDirectory.appendingPathComponent("test"))
        try ImmichClient.removeAccountCache(apiURL: client.apiURL, userID: testID)
        precondition(!FileManager.default.fileExists(atPath: cacheDirectory.path))
        let replacement = client.accountIsolated(userID: testID)
        precondition(replacement.session !== one.session)
        let otherID = testID + "-other"
        let two = client.accountIsolated(userID: otherID)
        defer { try? ImmichClient.removeAccountCache(apiURL: client.apiURL, userID: otherID) }
        precondition(client.accountIsolated(userID: testID).session === replacement.session)
        precondition(one.session !== two.session)
        precondition(one.session.configuration.urlCache !== two.session.configuration.urlCache)
        print("Account checks passed: live DTOs, older-server optionality, password/notification/multipart contracts, isolated caches.")
    }
}

final class AccountTestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if let body = request.httpBody { Self.lastBody = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            Self.lastBody = result
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
