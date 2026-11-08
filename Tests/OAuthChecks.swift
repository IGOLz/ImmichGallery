import Foundation
import Synchronization

/// Answers like an Immich server with OAuth on, and records what the client sent.
final class OAuthProtocol: URLProtocol, @unchecked Sendable {
    static let bodies = Mutex<[String: [String: String]]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let path = request.url!.path
        if !data.isEmpty { Self.bodies.withLock { $0[path] = try! JSONDecoder().decode([String: String].self, from: data) } }
        let answer: [String: Any] = switch path {
        case "/api/server/config": ["oauthButtonText": "Login with Authentik", "loginPageMessage": ""]
        case "/api/oauth/authorize": ["url": "https://idp.example.com/authorize?client_id=immich"]
        case "/api/oauth/callback": ["accessToken": "session-token", "userId": "u1", "userEmail": "a@example.com", "name": "A",
                                     "isAdmin": false, "profileImagePath": "", "shouldChangePassword": false, "isOnboarded": true]
        default: ["message": "Not found"]
        }
        let status = answer["message"] == nil ? 200 : 404
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: answer))
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OAuthChecks {
    static func main() async throws {
        // PKCE S256 (RFC 7636, section 4.2), checked against Python's hashlib and base64.urlsafe_b64encode.
        precondition(OAuthAttempt.challenge(for: "dBjftJeZ4CVP-mJ92K9qCo9vM-Iu4-Gs6v_KOBsGzfU") == "e73WDpX8jEjH2QEiXfy3KmeCrhaKLIhuG9IjJ_DPH9M")
        let fresh = try OAuthAttempt(), other = try OAuthAttempt()
        precondition(fresh.codeVerifier.count == 43 && fresh.state.count == 22, "256-bit verifier, 128-bit state")
        precondition(fresh.state != other.state && fresh.codeVerifier != other.codeVerifier)
        precondition(fresh.codeVerifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }, "base64url without padding")

        let attempt = OAuthAttempt(state: "state-1", codeVerifier: "verifier-1")
        let redirect = URL(string: "app.immich:///oauth-callback?code=c&state=state-1")!
        precondition(attempt.isRedirect(redirect))
        precondition(!attempt.isRedirect(URL(string: "app.immich:///oauth-callback?code=c&state=state-2")!), "another attempt's state")
        precondition(!attempt.isRedirect(URL(string: "app.immich:///oauth-callback?state=state-1")!), "no code")
        precondition(attempt.refusal(in: URL(string: "app.immich:///oauth-callback?error=access_denied&error_description=Not%20allowed&state=state-1")!) == "Not allowed")
        precondition(attempt.refusal(in: URL(string: "app.immich:///oauth-callback?error=access_denied&state=state-1")!) == "access_denied")
        precondition(attempt.refusal(in: URL(string: "app.immich:///oauth-callback?error=access_denied&state=state-2")!) == nil, "another attempt's refusal")
        precondition(attempt.refusal(in: redirect) == nil)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthProtocol.self]
        let client = ImmichClient(serverURL: URL(string: "https://photos.example.com")!, apiURL: URL(string: "https://photos.example.com/api")!,
                                  credential: nil, session: URLSession(configuration: config))

        let buttonText = await client.oauthButtonText()
        precondition(buttonText == "Login with Authentik")
        let provider = try await client.oauthAuthorize(attempt)
        precondition(provider.host() == "idp.example.com")
        precondition(OAuthProtocol.bodies.withLock { $0["/api/oauth/authorize"] } == [
            "redirectUri": "app.immich:///oauth-callback", "state": "state-1", "codeChallenge": OAuthAttempt.challenge(for: "verifier-1")])

        let login = try await client.oauthCallback(redirect, attempt)
        precondition(login.accessToken == "session-token")
        precondition(OAuthProtocol.bodies.withLock { $0["/api/oauth/callback"] } == [
            "url": "app.immich:///oauth-callback?code=c&state=state-1", "state": "state-1", "codeVerifier": "verifier-1"])

        for (address, expected) in [("app.immich:///oauth-callback?error=access_denied&state=state-1", "refused"),
                                    ("app.immich:///oauth-callback?code=c&state=state-2", "otherAttempt")] {
            do {
                _ = try await client.oauthCallback(URL(string: address)!, attempt)
                preconditionFailure("\(address) must not sign in")
            } catch let error as OAuthError {
                precondition(String(describing: error).hasPrefix(expected), "\(address): \(error)")
            }
        }
        print("OAuth checks passed: PKCE, state, provider refusals, authorize and callback bodies, button text.")
    }
}
