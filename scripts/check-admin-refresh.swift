// Compile with Models.swift, Models+Admin.swift and App/AdminModel.swift.
// These stand-ins exercise the production coordinator without network or app startup.
import Foundation

@MainActor final class AccountServices {
    let client = ImmichClient()
    let user: User? = try! JSONDecoder().decode(User.self, from: Data(#"{"id":"admin","name":"Admin","email":"admin@example.com","isAdmin":true}"#.utf8))
    var handledErrors = 0
    func handle(_ error: Error) { handledErrors += 1 }
}

enum ImmichError: Error { case http(Int, String?) }

@MainActor final class ImmichClient {
    static let userAgent = "AdminRefreshChecks"
    let serverURL: URL
    let apiURL: URL
    let credential: String?
    let session: URLSession
    var sent: [(String, String, [String: Any])] = []
    var accessChecks = 0
    var featureChecks = 0
    var queueReads = 0
    var failQueue = false
    var queueGate: CheckedContinuation<Void, Never>?
    var blockQueue = false

    init(serverURL: URL = URL(string: "https://example.invalid")!, apiURL: URL = URL(string: "https://example.invalid/api")!, credential: String? = nil, session: URLSession = .shared) {
        self.serverURL = serverURL; self.apiURL = apiURL
        self.credential = credential; self.session = session
    }
    func currentUser() async throws -> User {
        accessChecks += 1
        return try JSONDecoder().decode(User.self, from: Data(#"{"id":"admin","name":"Admin","email":"admin@example.com","isAdmin":true}"#.utf8))
    }
    func get<T>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        if path == "server/features" { featureChecks += 1 }
        if path == "queues" {
            queueReads += 1
            if blockQueue { await withCheckedContinuation { queueGate = $0 } }
            if failQueue { throw URLError(.notConnectedToInternet) }
            return [AdminQueue]() as! T
        }
        if path == "admin/users" { return [AdminUser]() as! T }
        if path == "libraries" { return [AdminLibrary]() as! T }
        return AdminValue.object([:]) as! T
    }
    func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        let encoded = try body.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as! [String: Any] } ?? [:]
        sent.append((method, path, encoded))
    }
    func send<T>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await send(method, path, body: body)
        return AdminValue.object([:]) as! T
    }

}

@main struct AdminRefreshChecks {
    @MainActor static func main() async {
        let session = AccountServices()
        let model = AdminModel(session: session)
        model.section = .queues
        let client = model.client
        assert(client.session.configuration.urlCache == nil)
        assert(client.session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        client.blockQueue = true
        let poll = Task { await model.refresh(polling: true) }
        while client.queueGate == nil { await Task.yield() }
        assert(model.isPolling && !model.busy)
        var performed = false
        let action = Task { await model.perform { performed = true } }
        while !model.busy { await Task.yield() }
        assert(!performed)
        client.blockQueue = false
        client.queueGate?.resume(); client.queueGate = nil
        await poll.value
        let success = await action.value
        assert(success && performed)
        assert(client.queueReads == 2) // Poll, then read after the mutation.
        assert(client.accessChecks == 1 && client.featureChecks == 1)
        assert(!model.busy && !model.isPolling)

        client.failQueue = true
        await model.refresh(polling: true)
        assert(model.pollingError != nil && model.error == nil && session.handledErrors == 0)
        let reads = client.queueReads
        await model.refresh(polling: true)
        assert(client.queueReads == reads) // Polling stays stopped until a manual retry.
        client.failQueue = false
        await model.refresh()
        assert(model.pollingError == nil)
        await model.refresh(polling: true)
        assert(client.queueReads == reads + 2)
        assert(client.accessChecks == 1 && client.featureChecks == 1)

        model.busy = true
        let rejected = await model.perform { assertionFailure("Must not overlap another mutation") }
        assert(!rejected && model.error != nil)
        model.busy = false
        try! await client.adminQueueCommand("faceDetection", command: "start", force: nil)
        assert(client.sent.last!.0 == "PUT" && client.sent.last!.1 == "jobs/faceDetection")
        assert(client.sent.last!.2["force"] == nil)
        try! await client.adminQueueCommand("faceDetection", command: "start")
        assert(client.sent.last!.2["force"] as? Bool == false)
        try! await client.adminQueueCommand("faceDetection", command: "start", force: true)
        assert(client.sent.last!.2["force"] as? Bool == true)
        try! await client.adminQueueCommand("faceDetection", command: "empty")
        assert(client.sent.last!.0 == "DELETE" && client.sent.last!.1 == "queues/faceDetection/jobs")
        assert(client.sent.last!.2["failed"] as? Bool == false)
        try! await client.adminQueueCommand("faceDetection", command: "clear-failed")
        assert(client.sent.last!.1 == "jobs/faceDetection")
        assert(client.sent.last!.2["command"] as? String == "clear-failed")
        print("Admin refresh checks passed: action waits for poll, cache disabled, silent failure, retry, access/features reuse")
    }
}
