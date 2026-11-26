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
                preconditionFailure("URLSession can bypass an explicit proxy for \(address)")
            } catch ImmichError.proxyRequiresHostname {}
        }
        do {
            try ServerProxy.validateOrigin(URL(string: "http://photos.example.test")!)
            preconditionFailure("Explicit proxies must require an HTTPS origin")
        } catch ImmichError.proxyRequiresHTTPS {}

        let legacy = Data(#"{"host":"127.0.0.1","port":3128,"username":"fixture","password":"initial"}"#.utf8)
        let proxy = try JSONDecoder().decode(ServerProxy.self, from: legacy)
        precondition(proxy.transport == .httpConnect && proxy.port == 3128 && proxy.password == "initial")
        let changed = try ServerProxy(transport: .httpConnect, host: "127.0.0.1", port: "3128", username: "fixture", password: "changed")
        let socks = try ServerProxy(transport: .socks5, host: "127.0.0.1", port: "3128", username: "fixture", password: "changed")
        let anonymous = try ServerProxy(transport: .socks5, host: "127.0.0.1", port: "3128", username: "", password: "")
        precondition(anonymous.username == nil && anonymous.password == nil)
        for profile in [proxy, socks, anonymous] {
            let roundTrip = try JSONDecoder().decode(ServerProxy.self, from: JSONEncoder().encode(profile))
            precondition(roundTrip == profile)
        }
        for secret in ["", String(repeating: "é", count: 128)] {
            do {
                _ = try ServerProxy(transport: .socks5, host: "127.0.0.1", port: "3128", username: "fixture", password: secret)
                preconditionFailure("SOCKS5 credentials must each fit in one length byte")
            } catch ImmichError.invalidSOCKS5Credentials {}
        }
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
        let socksAccount = ImmichClient(serverURL: server, apiURL: api, credential: nil, proxy: socks).accountIsolated(userID: user)
        precondition(socksAccount.session !== updated.session)
        precondition(socksAccount.proxy?.transport == .socks5)
        precondition(socksAccount.session.configuration.proxyConfigurations.first?.allowFailover == false)
        do {
            _ = try await updated.data(for: updated.request("server/ping"))
            preconditionFailure("A transport-only edit did not retire the old route")
        } catch is CancellationError {}
        let other = ImmichClient(serverURL: alias, apiURL: api, credential: nil).accountIsolated(userID: user)
        precondition(other.session !== socksAccount.session)
        precondition(other.session.configuration.proxyConfigurations.isEmpty)

        let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EAUTH.rawValue))
        guard case ImmichError.proxyAuthentication = ImmichClient.proxyError(denied) else {
            preconditionFailure("A rejected CONNECT login must stay separate from Immich's 401")
        }
        print("Legacy profiles, HTTP CONNECT and SOCKS5 settings, and session isolation passed.")
    }
}
