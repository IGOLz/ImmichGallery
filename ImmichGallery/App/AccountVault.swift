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
        var serverProxies: [String: ServerProxy]?
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
    private static func write(_ contents: Contents, removing: Bool = false) throws {
        let previous = try read()
        guard removing || !contents.entries.isEmpty || previous.entries.isEmpty else {
            throw ImmichError.http(400, String(localized: "Refusing to overwrite saved accounts with an empty list."))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(contents)
        let verified = try JSONDecoder().decode(Contents.self, from: data)
        guard try encoder.encode(verified) == data else {
            throw ImmichError.http(400, String(localized: "Could not verify saved accounts."))
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "Immich Gallery accounts"]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item.merge(attributes) { _, new in new }
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
    static func loadEntries() throws -> [Entry] { try read().entries }
    static func loadProxies() throws -> [String: ServerProxy] { try read().serverProxies ?? [:] }

    static func client(for account: AccountStore.Account) throws -> ImmichClient {
        let proxy = try loadProxies()[ServerProxy.serverKey(account.serverURL)]
        return try client(for: account, proxy: proxy)
    }

    static func client(for account: AccountStore.Account, proxy: ServerProxy?) throws -> ImmichClient {
        if proxy != nil {
            try ServerProxy.validateOrigin(account.serverURL)
            try ServerProxy.validateOrigin(account.apiURL)
        }
        return ImmichClient(serverURL: account.serverURL, apiURL: account.apiURL, credential: account.credential, proxy: proxy)
    }

    static func saveProxy(_ proxy: ServerProxy?, for serverURL: URL) throws {
        var contents = try read()
        setProxy(proxy, for: serverURL, in: &contents)
        try write(contents)
    }

    private static func setProxy(_ proxy: ServerProxy?, for serverURL: URL, in contents: inout Contents) {
        var proxies = contents.serverProxies ?? [:]
        proxies[ServerProxy.serverKey(serverURL)] = proxy
        contents.serverProxies = proxies.isEmpty ? nil : proxies
    }
    static func selectedEntry() throws -> Entry? {
        let contents = try read()
        return contents.entries.first { $0.id == contents.selected }
    }
    static func save(account: AccountStore.Account, user: User) throws {
        try save(account: account, user: user, in: read())
    }

    static func save(account: AccountStore.Account, user: User, proxy: ServerProxy?) throws {
        var contents = try read()
        setProxy(proxy, for: account.serverURL, in: &contents)
        try save(account: account, user: user, in: contents)
    }

    private static func save(account: AccountStore.Account, user: User, in previous: Contents) throws {
        var contents = previous
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
        guard contents.entries.contains(where: { $0.id == id }) else {
            throw ImmichError.http(400, String(localized: "This account is no longer saved."))
        }
        contents.selected = id
        try write(contents)
    }
    static func remove(_ id: String) throws {
        var contents = try read()
        contents.entries.removeAll { $0.id == id }
        if contents.selected == id { contents.selected = nil }
        try write(contents, removing: true)
    }
}
