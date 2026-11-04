// Run with the Admin DTOs and shared models, as documented in docs/Admin.md.
import Foundation

@main struct AdminModelChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        let emptyQuota = AdminUserInput(name: "Test", email: "test@example.com", isAdmin: false, password: nil, shouldChangePassword: true, quotaSizeInBytes: nil)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(emptyQuota)) as! [String: Any]
        assert(body["quotaSizeInBytes"] is NSNull)
        assert(body["password"] == nil)
        let user = try decoder.decode(User.self, from: Data(#"{"id":"test","name":"Test","email":"test@example.com"}"#.utf8))
        assert(user.isAdmin != true)
        let value = try decoder.decode(AdminValue.self, from: Data(#"{"flag":true,"count":12,"nested":[null,"text"]}"#.utf8))
        assert(value["flag"]?.boolValue == true)
        assert(value["count"]?.display == "12")
        let queue = try decoder.decode(AdminQueue.self, from: Data(#"{"name":"backgroundTask","isPaused":false,"statistics":{"active":0,"completed":0,"delayed":0,"failed":0,"paused":0,"waiting":0}}"#.utf8))
        assert(!queue.canStart)
        assert(AdminQueue.managedNames.count == 12)
        assert(!AdminQueue.managedNames.contains("backgroundTask"))
        assert(AdminQuota.bytes(from: "1.5") == 1_610_612_736)
        assert(AdminQuota.bytes(from: "0") == 0)
        assert(AdminQuota.bytes(from: "") == nil)
        for invalid in ["-1", "nan", "inf", "9007199254740991", "bad"] {
            assert(AdminQuota.bytes(from: invalid) == nil)
        }
        for bytes: Int64 in [0, 1, 1_610_612_736, 9_007_199_254_740_991] {
            assert(AdminQuota.bytes(from: AdminQuota.text(from: bytes)) == bytes)
        }
        assert(AdminValue.string("sensitive").display(forKey: "password") == "Hidden")
        assert(AdminValue.string("sensitive").display(forKey: "clientSecret") == "Hidden")
        assert(AdminValue.string("sensitive").display(forKey: "apiKey") == "Hidden")
        assert(AdminValue.string("sensitive").display(forKey: "secret") == "Hidden")
        assert(AdminValue.string("client_secret_post").display(forKey: "tokenEndpointAuthMethod") == "client_secret_post")
        assert(AdminValue.bool(true).display(forKey: "passwordLogin") == "Yes")
        let bytes = AdminValue.number(1_610_612_736)
        let formatted = ByteCountFormatter.string(fromByteCount: 1_610_612_736, countStyle: .file)
        for key in ["usage", "usagePhotos", "diskSizeRaw", "diskAvailableRaw"] {
            assert(bytes.display(forKey: key) == formatted)
        }
        assert(bytes.display(forKey: "photos") == "1610612736")
        if let directory = CommandLine.arguments.dropFirst().first {
            func data(_ name: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("immich-admin-\(name).json")) }
            let me = try decoder.decode(User.self, from: data("users-me"))
            let users = try decoder.decode([AdminUser].self, from: data("admin-users"))
            let queues = try decoder.decode([AdminQueue].self, from: data("queues"))
            _ = try decoder.decode([AdminLibrary].self, from: data("libraries"))
            for name in ["server-statistics", "server-storage", "server-version-check", "system-config"] {
                _ = try decoder.decode(AdminValue.self, from: data(name))
            }
            assert(me.isAdmin == true && !users.isEmpty && !queues.isEmpty)
            print("Live v3.3.5 DTO checks passed: admin user, users, queues, libraries, statistics, storage, version check, configuration")
        }
        print("Admin model checks passed")
    }
}
