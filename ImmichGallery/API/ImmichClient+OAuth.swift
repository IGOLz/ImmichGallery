import CryptoKit
import Foundation
import Security

/// One browser sign-in (OIDC), the way the Immich mobile app does it: the server is the OAuth client, the app sends a
/// PKCE challenge (S256) and a state, and the identity provider ends at the mobile app's redirect URI. Servers set up
/// for the phone app already allow that URI, so no server or provider changes are needed. On servers with Immich's
/// "mobile redirect override", the provider goes to `<server>/api/oauth/mobile-redirect`, which bounces to the same URI.
struct OAuthAttempt: Sendable {
    static let redirectURI = "app.immich:///oauth-callback"
    static let callbackScheme = "app.immich"

    let state: String
    let codeVerifier: String
    var codeChallenge: String { Self.challenge(for: codeVerifier) }

    /// Fresh secrets: a 256-bit verifier and a 128-bit state.
    init() throws {
        try self.init(state: Self.randomText(byteCount: 16), codeVerifier: Self.randomText(byteCount: 32))
    }

    init(state: String, codeVerifier: String) {
        self.state = state
        self.codeVerifier = codeVerifier
    }

    /// The S256 challenge for a verifier (RFC 7636, section 4.2).
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Whether the address the provider sent the browser to ends this attempt: it carries a code and our state.
    func isRedirect(_ redirect: URL) -> Bool {
        let items = Self.queryItems(redirect)
        return items["code"]?.isEmpty == false && items["state"] == state
    }

    /// The provider's refusal (`error`, with our state), as a message for people.
    func refusal(in redirect: URL) -> String? {
        let items = Self.queryItems(redirect)
        guard let error = items["error"], items["state"] == state else { return nil }
        return items["error_description"].flatMap { $0.isEmpty ? nil : $0 } ?? error
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private static func randomText(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else { throw OAuthError.noRandomness }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case noRandomness
    case invalidProviderURL
    case refused(String)
    case otherAttempt

    var errorDescription: String? {
        switch self {
        case .noRandomness:
            String(localized: "Couldn't start single sign-on. Please try again.")
        case .invalidProviderURL:
            String(localized: "The server sent a sign-in address that can't be opened.")
        case .refused(let message):
            String(localized: "The sign-in provider refused: \(message)")
        case .otherAttempt:
            String(localized: "That sign-in belongs to another attempt. Please sign in again.")
        }
    }
}

extension ImmichClient {
    /// The label of the server's single sign-on button, as Immich's web app shows it.
    func oauthButtonText() async -> String {
        struct Config: Decodable { var oauthButtonText: String? }
        let config: Config? = try? await get("server/config")
        let text = config?.oauthButtonText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? String(localized: "Sign in with SSO") : text
    }

    /// Starts browser sign-in: the identity provider's address to open.
    func oauthAuthorize(_ attempt: OAuthAttempt) async throws -> URL {
        struct Body: Encodable { let redirectUri: String; let state: String; let codeChallenge: String }
        struct Answer: Decodable { let url: String }
        let answer: Answer = try await send("POST", "oauth/authorize", body: Body(
            redirectUri: OAuthAttempt.redirectURI, state: attempt.state, codeChallenge: attempt.codeChallenge))
        guard let url = URL(string: answer.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw OAuthError.invalidProviderURL
        }
        return url
    }

    /// Finishes browser sign-in with the address the provider sent the browser to. The answer holds a session token.
    func oauthCallback(_ redirect: URL, _ attempt: OAuthAttempt) async throws -> LoginResponse {
        if let refusal = attempt.refusal(in: redirect) { throw OAuthError.refused(refusal) }
        guard attempt.isRedirect(redirect) else { throw OAuthError.otherAttempt }
        struct Body: Encodable { let url: String; let state: String; let codeVerifier: String }
        return try await send("POST", "oauth/callback", body: Body(
            url: redirect.absoluteString, state: attempt.state, codeVerifier: attempt.codeVerifier))
    }
}
