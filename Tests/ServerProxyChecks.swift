import Foundation
import Network

@main enum ServerProxyChecks {
    static func main() async throws {
        let server = URL(string: "https://photos.example.test/gallery")!
        let alias = URL(string: "https://alias.example.test/gallery")!
        let api = URL(string: "https://api.example.test/photos/api")!
        precondition(ServerProxy.serverKey(URL(string: "HTTPS://PHOTOS.EXAMPLE.TEST:443/gallery/")!) == server.absoluteString)
        precondition(ServerProxy.serverKey(URL(string: "https://photos.example.test:2283/gallery")!) != server.absoluteString)
        precondition(ServerProxy.serverKey(URL(string: "https://photos.example.test")!) != server.absoluteString)
        try ServerProxy.validateOrigin(server)
        for address in ["https://localhost.", "https://127.0.0.1", "https://2130706433", "https://192.0.2.10", "https://[::1]"] {
            do {
                try ServerProxy.validateOrigin(URL(string: address)!)
                preconditionFailure("URLSession can bypass HTTP CONNECT for \(address)")
            } catch ImmichError.proxyRequiresHostname {}
        }
        do {
            try ServerProxy.validateOrigin(URL(string: "http://photos.example.test")!)
            preconditionFailure("HTTP CONNECT must require an HTTPS origin")
        } catch ImmichError.proxyRequiresHTTPS {}

        let proxy = try ServerProxy(host: "127.0.0.1", port: "3128", username: "fixture", password: "initial")
        let changed = try ServerProxy(host: "127.0.0.1", port: "3128", username: "fixture", password: "changed")
        let user = "proxy-check-\(UUID().uuidString)"
        defer { try? ImmichClient.removeAccountCache(apiURL: api, userID: user) }
        let direct = ImmichClient(serverURL: server, apiURL: api, credential: nil).accountIsolated(userID: user)
        let proxied = ImmichClient(serverURL: server, apiURL: api, credential: nil, proxy: proxy)
        let signedIn = proxied.with(credential: .apiKey("test"))
        precondition(signedIn.session === proxied.session)
        precondition(signedIn.proxy == proxy)
        let account = signedIn.accountIsolated(userID: user)
        precondition(direct.session !== account.session)
        precondition(account.session === signedIn.accountIsolated(userID: user).session)
        precondition(account.session.configuration.proxyConfigurations.first?.allowFailover == false)
        let isolated = account.isolatedClient(.ephemeral)
        precondition(isolated.session.configuration.proxyConfigurations.count == 1)
        let started = AsyncStream<Void>.makeStream()
        let inFlight = Task {
            try await isolated.withSession { _ in
                started.continuation.yield(())
                try await Task.sleep(for: .seconds(2))
            }
        }
        for await _ in started.stream { break }
        let updated = ImmichClient(serverURL: server, apiURL: api, credential: nil, proxy: changed).accountIsolated(userID: user)
        precondition(updated.session !== account.session)
        do {
            try await inFlight.value
            preconditionFailure("A route change left an old request running")
        } catch is CancellationError {}
        for stale in [account, isolated, direct] {
            do {
                _ = try await stale.data(for: stale.request("server/ping"))
                preconditionFailure("A retired account route accepted another request")
            } catch is CancellationError {}
        }
        let other = ImmichClient(serverURL: alias, apiURL: api, credential: nil).accountIsolated(userID: user)
        precondition(other.session !== updated.session)
        precondition(other.session.configuration.proxyConfigurations.isEmpty)

        let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EAUTH.rawValue))
        guard case ImmichError.proxyAuthentication = ImmichClient.proxyError(denied) else {
            preconditionFailure("A rejected CONNECT login must stay separate from Immich's 401")
        }
        print("HTTP CONNECT settings, failover policy, and session isolation passed.")
    }
}
