import Foundation
import Observation

@MainActor @Observable
final class AdminModel {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Server", queues = "Jobs", users = "Users", libraries = "External Libraries", settings = "Server Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: "server.rack"
            case .queues: "list.bullet.rectangle"
            case .users: "person.2"
            case .libraries: "externaldrive"
            case .settings: "gearshape"
            }
        }
    }
    let session: LibrarySession
    var section: Section = .overview
    var unavailable: Set<Section> = []
    var authorized = true
    var busy = false
    var error: String?
    var users: [AdminUser] = []
    var libraries: [AdminLibrary] = []
    var queues: [AdminQueue] = []
    var overview: [String: AdminValue] = [:]
    var settings: AdminValue?
    var featureFlags: AdminValue?
    var notice: String?

    init(session: LibrarySession) { self.session = session }

    func checkAccess() async throws {
        guard session.user?.isAdmin == true else { authorized = false; throw ImmichError.http(403, "Administrator access is required.") }
        let user = try await session.client.currentUser()
        guard user.isAdmin == true else {
            authorized = false
            users = []; libraries = []; queues = []; overview = [:]; settings = nil
            throw ImmichError.http(403, "Administrator access is required.")
        }
    }

    func refresh() async {
        guard !busy, authorized, !unavailable.contains(section) else { return }
        busy = true
        let target = section
        defer { busy = false }
        do {
            try await checkAccess()
            switch target {
            case .overview:
                for (title, path) in [("Statistics", "server/statistics"), ("Storage", "server/storage"),
                                      ("Version", "server/version"), ("Version Check", "server/version-check")] {
                    do { overview[title] = try await session.client.get(path) }
                    catch ImmichError.http(404, _) { overview.removeValue(forKey: title) }
                }
            case .queues:
                featureFlags = try await session.client.get("server/features")
                queues = try await session.client.adminQueues()
            case .users: users = try await session.client.adminUsers()
            case .libraries:
                libraries = try await session.client.adminLibraries()
                users = try await session.client.adminUsers()
            case .settings: settings = try await session.client.get("system-config")
            }
        } catch ImmichError.http(404, _) {
            unavailable.insert(target)
        } catch { report(error) }
    }

    func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !busy, authorized else { return false }
        busy = true
        error = nil
        do {
            try await checkAccess()
            try await operation()
            busy = false
            await refresh()
            return true
        } catch {
            busy = false
            report(error)
            return false
        }
    }

    func canStart(_ queue: AdminQueue) -> Bool {
        let flag = ["smartSearch": "smartSearch", "duplicateDetection": "duplicateDetection",
                    "faceDetection": "facialRecognition", "facialRecognition": "facialRecognition",
                    "sidecar": "sidecar", "ocr": "ocr"][queue.name]
        return queue.canStart && (flag.map { featureFlags?[$0]?.boolValue == true } ?? true)
    }

    private func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        self.error = error.localizedDescription
        session.handle(error)
    }
}
