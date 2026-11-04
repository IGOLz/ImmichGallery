import Foundation
import Observation

@MainActor @Observable
final class AdminModel {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Server", queues = "Jobs", users = "Users", libraries = "External Libraries", settings = "Server Settings"
        var title: LocalizedStringResource {
            switch self {
            case .overview: "Server"
            case .queues: "Jobs"
            case .users: "Users"
            case .libraries: "External Libraries"
            case .settings: "Server Settings"
            }
        }
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
    var isPolling = false
    var pollingError: String?
    private var refreshTask: Task<Void, Never>?
    private var lastAccessCheck: Date?
    let client: ImmichClient
    var error: String?
    var users: [AdminUser] = []
    var libraries: [AdminLibrary] = []
    var queues: [AdminQueue] = []
    var overview: [String: AdminValue] = [:]
    var settings: AdminValue?
    var featureFlags: AdminValue?
    var notice: String?

    init(session: LibrarySession) {
        self.session = session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": ImmichClient.userAgent]
        configuration.timeoutIntervalForRequest = 30
        client = ImmichClient(serverURL: session.client.serverURL, apiURL: session.client.apiURL,
                              credential: session.client.credential, session: URLSession(configuration: configuration))
    }

    func checkAccess() async throws {
        guard session.user?.isAdmin == true else { authorized = false; throw ImmichError.http(403, String(localized: "Administrator access is required.")) }
        if let lastAccessCheck, Date().timeIntervalSince(lastAccessCheck) < 60 { return }
        let user = try await client.currentUser()
        guard user.isAdmin == true else {
            authorized = false
            users = []; libraries = []; queues = []; overview = [:]; settings = nil
            throw ImmichError.http(403, String(localized: "Administrator access is required."))
        }
        lastAccessCheck = Date()
    }

    func refresh(polling: Bool = false) async {
        let target = section
        while let refreshTask {
            await refreshTask.value
            if target != section { return }
        }
        guard !busy, authorized, !unavailable.contains(target), !Task.isCancelled else { return }
        if polling && pollingError != nil { return }
        isPolling = true
        refreshTask = Task {
            defer { isPolling = false; refreshTask = nil }
            await load(target, polling: polling)
        }
        if let refreshTask {
            await withTaskCancellationHandler {
                await refreshTask.value
            } onCancel: {
                refreshTask.cancel()
            }
        }
    }

    private func load(_ target: Section, polling: Bool) async {
        do {
            try await checkAccess()
            switch target {
            case .overview:
                for (title, path) in [("Statistics", "server/statistics"), ("Storage", "server/storage"),
                                      ("Version", "server/version"), ("Version Check", "server/version-check")] {
                    do { overview[title] = try await client.get(path) }
                    catch ImmichError.http(404, _) { overview.removeValue(forKey: title) }
                }
            case .queues:
                if featureFlags == nil { featureFlags = try await client.get("server/features") }
                queues = try await client.adminQueues()
            case .users: users = try await client.adminUsers()
            case .libraries:
                libraries = try await client.adminLibraries()
                users = try await client.adminUsers()
            case .settings: settings = try await client.get("system-config")
            }
            pollingError = nil
        } catch ImmichError.http(404, _) {
            unavailable.insert(target)
        } catch {
            if polling {
                if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                    pollingError = String(localized: "Automatic refresh stopped: \(error.localizedDescription) Use Refresh to retry.")
                }
            } else { report(error) }
        }
    }

    func perform(_ operation: () async throws -> Void) async -> Bool {
        guard authorized else { error = String(localized: "Administrator access is required."); return false }
        guard !busy else { error = String(localized: "Another operation is running. Please try again."); return false }
        busy = true
        error = nil
        await refreshTask?.value
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
