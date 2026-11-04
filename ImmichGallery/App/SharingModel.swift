import Foundation
import Observation

@MainActor @Observable
final class SharingModel {
    let client: ImmichClient
    var presentation: SharingPresentation?
    var links: [SharedLink] = []
    var receivedPartners: [SharingPartner] = []
    var outgoingPartners: [SharingPartner] = []
    var linksAvailable = true
    var partnersAvailable = true
    var error: String?
    var backgroundError: String?
    var busy = false

    init(client: ImmichClient) { self.client = client }

    func reload() async {
        var linksAvailable = self.linksAvailable
        var partnersAvailable = self.partnersAvailable
        var backgroundError: String?
        do { links = try await client.sharedLinks(); linksAvailable = true }
        catch ImmichError.http(404, _) { linksAvailable = false }
        catch { backgroundError = error.localizedDescription }
        do {
            let received = try await client.sharingPartners(direction: "shared-with")
            let outgoing = try await client.sharingPartners(direction: "shared-by")
            receivedPartners = received
            outgoingPartners = outgoing
            partnersAvailable = true
        } catch ImmichError.http(404, _) { partnersAvailable = false }
        catch { backgroundError = error.localizedDescription }
        // Missing preference subtrees on older servers leave sharing available.
        struct Preferences: Decodable {
            struct Enabled: Decodable { var enabled: Bool? }
            var sharedLinks: Enabled?
        }
        if let preferences: Preferences = try? await client.get("users/me/preferences") {
            if preferences.sharedLinks?.enabled == false { linksAvailable = false }
        }
        self.linksAvailable = linksAvailable
        self.partnersAvailable = partnersAvailable
        self.backgroundError = backgroundError
    }

    @discardableResult
    func perform(_ action: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        error = nil
        busy = true
        defer { busy = false }
        do { try await action(); await reload(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
