import Foundation
import Security

enum AccountVault {
    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var email: String
        var userID: String
        var account: AccountStore.Account
    }
    private struct Contents: Codable {
        var entries: [Entry] = []
        var selected: String?
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "ImmichGallery",
         kSecAttrAccount as String: "accounts-v1"]
    }
    private static func read() throws -> Contents {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return Contents() }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(Contents.self, from: data)
    }
    private static func write(_ contents: Contents) throws {
        let data = try JSONEncoder().encode(contents)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not save accounts to Keychain (\(status))."])
        }
    }
    // Copy the legacy credential once, leaving its original Keychain item intact.
    static var legacyAccountForMigration: AccountStore.Account? {
        UserDefaults.standard.bool(forKey: "accountVaultMigrated") ? nil : AccountStore.load()
    }
    static var entries: [Entry] { (try? read().entries) ?? [] }
    static var selected: Entry? {
        let contents = try? read()
        return contents?.entries.first { $0.id == contents?.selected }
    }
    static func save(account: AccountStore.Account, user: User) throws {
        var contents = try read()
        let id = account.apiURL.absoluteString + "|" + user.id
        let entry = Entry(id: id, name: user.name, email: user.email, userID: user.id, account: account)
        contents.entries.removeAll { $0.id == id }
        contents.entries.append(entry)
        contents.selected = id
        try write(contents)
        AccountStore.lastServer = account.serverURL.absoluteString
        UserDefaults.standard.set(true, forKey: "accountVaultMigrated")
    }
    static func select(_ id: String) throws {
        var contents = try read()
        contents.selected = id
        try write(contents)
    }
    static func remove(_ id: String) throws {
        var contents = try read()
        contents.entries.removeAll { $0.id == id }
        if contents.selected == id { contents.selected = nil }
        try write(contents)
    }
}
