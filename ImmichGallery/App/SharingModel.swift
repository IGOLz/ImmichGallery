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
    var busy = false

    init(client: ImmichClient) { self.client = client }

    func reload() async {
        do { links = try await client.sharedLinks(); linksAvailable = true }
        catch ImmichError.http(404, _) { linksAvailable = false }
        catch { self.error = error.localizedDescription }
        do {
            partnersAvailable = true
            receivedPartners = try await client.sharingPartners(direction: "shared-with")
            outgoingPartners = try await client.sharingPartners(direction: "shared-by")
        } catch ImmichError.http(404, _) { partnersAvailable = false }
        catch { self.error = error.localizedDescription }
        // Missing preference subtrees on older servers leave sharing available.
        struct Preferences: Decodable {
            struct Enabled: Decodable { var enabled: Bool? }
            var sharedLinks: Enabled?
        }
        if let preferences: Preferences = try? await client.get("users/me/preferences") {
            if preferences.sharedLinks?.enabled == false { linksAvailable = false }
        }
    }

    func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await action(); await reload() }
        catch { self.error = error.localizedDescription }
    }
}
