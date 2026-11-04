import Foundation
import Observation

@MainActor @Observable
final class AccountOperation {
    var busy = false
    var error: String?
    var message: String?
    var unavailable = false

    func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        message = nil
        Task {
            defer { busy = false }
            do { try await work() }
            catch ImmichError.http(404, _) { unavailable = true; error = "This feature is unavailable on this server." }
            catch { self.error = error.localizedDescription }
        }
    }
}
