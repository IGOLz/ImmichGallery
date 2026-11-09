import Foundation
import Observation

@MainActor @Observable
final class AccountOperation {
    var busy = false
    var error: String?
    var message: String?
    var unavailable = false

    func run(probe: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        message = nil
        Task {
            defer { busy = false }
            do { try await work() }
            catch ImmichError.http(404, _) where probe { unavailable = true; error = String(localized: "This feature is unavailable on this server.") }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Dates from Immich may include fractional seconds.
func accountDate(_ value: String) -> String {
    accountDateValue(value)?.formatted(date: .abbreviated, time: .shortened) ?? value
}

func accountDateValue(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
