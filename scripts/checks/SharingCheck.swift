// Compile with Models.swift, ImmichClient.swift and their +Sharing extensions.
// Optional argument: directory containing the live-*.json verification captures.
import Foundation

@main struct SharingCheck {
    static func main() async throws {
        let decoder = JSONDecoder()
        let fixture = Data(#"{"id":"id","key":"abc-_123","type":"INDIVIDUAL","allowDownload":true,"allowUpload":false,"showMetadata":true,"assets":[]}"#.utf8)
        var link = try decoder.decode(SharedLink.self, from: fixture)
        precondition(!link.hasPassword)
        link.password = ""
        precondition(!link.hasPassword)
        link.password = "masked"
        precondition(link.hasPassword)
        let server = URL(string: "https://internal.example/base")!
        let keyURL = try ImmichClient.sharingURL(link, externalDomain: "", serverURL: server)
        precondition(keyURL.absoluteString == "https://internal.example/share/abc-_123")
        link.slug = "a/b ?#é"
        let slugURL = try ImmichClient.sharingURL(link, externalDomain: "https://public.example", serverURL: server)
        precondition(slugURL.absoluteString == "https://public.example/s/a%2Fb%20%3F%23%C3%A9")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UnavailableSharingConfig.self]
        let client = ImmichClient(serverURL: server, apiURL: server.appendingPathComponent("api"), credential: nil, session: URLSession(configuration: config))
        let fallback = try await client.sharingPublicURL(link)
        precondition(fallback.absoluteString == "https://internal.example/s/a%2Fb%20%3F%23%C3%A9")
        var options = SharingOptions()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as! [String: Any]
        precondition(object["password"] is NSNull && object["expiresAt"] is NSNull && object["slug"] is NSNull)
        options.keepPassword = true
        object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as! [String: Any]
        precondition(object["password"] == nil)
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name + ".json")) }
            _ = try decoder.decode([SharedLink].self, from: data("live-shared-links"))
            for name in ["live-created-link", "live-edited-link", "live-album-link"] {
                _ = try decoder.decode(SharedLink.self, from: data(name))
            }
            for direction in ["by", "with"] {
                _ = try decoder.decode([SharingPartner].self, from: data("live-partners-" + direction))
            }
            _ = try decoder.decode([User].self, from: data("live-users"))
            _ = try decoder.decode([AssetResponse].self, from: data("live-assets"))
            _ = try decoder.decode(TimeBucketAssets.self, from: data("live-partner-bucket"))
        }
        print("Sharing checks passed")
    }
}

// Intercept every request so this check never reaches a live server.
private final class UnavailableSharingConfig: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url?.path == "/base/api/server/config")
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
