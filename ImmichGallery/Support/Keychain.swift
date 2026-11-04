import Foundation
import Security

/// Stores the signed-in account (server + credential) in the user's keychain.
enum AccountStore {
    struct Account: Codable {
        var serverURL: URL
        var apiURL: URL
        var credential: Credential
    }

    private static let service = Bundle.main.bundleIdentifier ?? "ImmichGallery"
    private static let accountKey = "account"
    private static let lastServerKey = "lastServerURL"

    static var lastServer: String? {
        get { UserDefaults.standard.string(forKey: lastServerKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastServerKey) }
    }

    static func load() -> Account? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func save(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel as String] = "Immich Gallery (\(account.serverURL.host() ?? ""))"
        SecItemAdd(item as CFDictionary, nil)
        lastServer = account.serverURL.absoluteString
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
    }
}
