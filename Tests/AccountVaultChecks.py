"""Exercise the real vault code against a unique test-only Keychain service.

No app launch, network calls, real AccountStore implementation, or real defaults.
"""
import pathlib
import subprocess
import uuid

root = pathlib.Path(__file__).resolve().parents[1]
output = root / 'build/AccountVaultChecks'
output.mkdir(parents=True, exist_ok=True)
service = 'ImmichGallery.AccountVaultChecks.' + str(uuid.uuid4())
vault = (root / 'ImmichGallery/App/AccountVault.swift').read_text()
vault = vault.replace('Bundle.main.bundleIdentifier ?? "ImmichGallery"', '"' + service + '"')
vault = vault.replace('UserDefaults.standard', 'UserDefaults(suiteName: "' + service + '")!')
(output / 'AccountVault.swift').write_text(vault)
checks = r'''
import Foundation
import Security

enum AccountStore {
    struct Account: Codable {
        var serverURL: URL
        var apiURL: URL
        var credential: Credential
    }
    nonisolated(unsafe) static var lastServer: String?
    static func load() -> Account? { fatalError("Tests must not load legacy credentials") }
}

@main struct VaultChecks {
    @MainActor static func main() async throws {
        let service = "TEST_SERVICE"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "accounts-v1"]
        defer {
            SecItemDelete(query as CFDictionary)
            UserDefaults(suiteName: service)!.removePersistentDomain(forName: service)
        }
        let user = try JSONDecoder().decode(User.self, from: Data("""
        {"id":"test-user", "email":"test@example.invalid", "name":"Test", "shouldChangePassword":true}
        """.utf8))
        precondition(user.shouldChangePassword == true)
        let account = AccountStore.Account(serverURL: URL(string: "https://demo.immich.app")!,
            apiURL: URL(string: "https://demo.immich.app/api")!, credential: .accessToken("test-only"))
        try AccountVault.save(account: account, user: user)
        let selected = try AccountVault.selectedEntry()!
        precondition(selected.account.credential == account.credential)
        UserDefaults(suiteName: service)!.set(false, forKey: "accountVaultMigrated")
        let restored = try AccountVault.selectedEntry()?.account ?? AccountVault.legacyAccountForMigration
        precondition(restored?.credential == account.credential)
        UserDefaults(suiteName: service)!.set(true, forKey: "accountVaultMigrated")
        precondition(AccountVault.legacyAccountForMigration == nil)
        precondition(try AccountVault.loadEntries().count == 1)
        do { try AccountVault.select("missing"); preconditionFailure() } catch {}
        precondition(try AccountVault.selectedEntry()?.id == selected.id)
        let corrupt = Data("invalid-json".utf8)
        precondition(SecItemUpdate(query as CFDictionary, [kSecValueData as String: corrupt] as CFDictionary) == errSecSuccess)
        do { try AccountVault.remove(selected.id); preconditionFailure() } catch {}
        do { try AccountVault.save(account: account, user: user); preconditionFailure() } catch {}
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        var result: CFTypeRef?
        precondition(SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess)
        precondition(result as? Data == corrupt)
        SecItemDelete(query as CFDictionary)
        try AccountVault.save(account: account, user: user)
        try AccountVault.remove(selected.id)
        precondition(try AccountVault.selectedEntry() == nil)
        precondition(try AccountVault.loadEntries().isEmpty)
        let mutation = AccountOperation()
        mutation.run { throw ImmichError.http(404, "Already deleted") }
        while mutation.busy { await Task.yield() }
        precondition(!mutation.unavailable && mutation.error == "Already deleted")
        let probe = AccountOperation()
        probe.run(probe: true) { throw ImmichError.http(404, nil) }
        while probe.busy { await Task.yield() }
        precondition(probe.unavailable)
        precondition(accountDate("2026-01-01T00:00:00.123Z") != "2026-01-01T00:00:00.123Z")
        precondition(accountDate("2026-01-01T00:00:00Z") != "2026-01-01T00:00:00Z")
        print("Vault/operation checks passed; temporary test service removed.")
    }
}
'''.replace('TEST_SERVICE', service)
# precondition's autoclosure cannot throw.
checks = checks.replace('precondition(try ', 'precondition(try! ')
(output / 'Checks.swift').write_text(checks)
sources = [str(p.relative_to(root)) for p in sorted((root / 'ImmichGallery/API').glob('*.swift'))] + ['ImmichGallery/App/AccountOperation.swift']
subprocess.run(['swiftc', '-swift-version', '6', *sources, str(output / 'AccountVault.swift'),
                str(output / 'Checks.swift'), '-o', str(output / 'check')], cwd=root, check=True)
subprocess.run([str(output / 'check')], cwd=root, check=True)
