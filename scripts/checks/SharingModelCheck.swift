// Compile with Models.swift, ImmichClient.swift, their +Sharing extensions and SharingModel.swift.
import Foundation

// The presentation view is outside this model-only check.
struct SharingPresentation {}

@main struct SharingModelCheck {
    @MainActor static func main() async {
        func model(_ scenario: String) -> SharingModel {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [SharingModelResponses.self]
            let server = URL(string: "https://demo.immich.app")!
            return SharingModel(client: ImmichClient(serverURL: server, apiURL: server.appendingPathComponent(scenario), credential: nil, session: URLSession(configuration: config)))
        }
        let failing = model("failure")
        await failing.reload()
        precondition(failing.backgroundError != nil && failing.error == nil)

        let sharing = model("success")
        sharing.linksAvailable = false
        await sharing.reload()
        precondition(!sharing.linksAvailable && sharing.partnersAvailable)
        precondition(sharing.backgroundError == nil)
        sharing.error = "Previous action failed"
        let succeeded = await sharing.perform {}
        precondition(succeeded && sharing.error == nil)
        let failed = await sharing.perform { throw ImmichError.http(400, "Action failed") }
        precondition(!failed && sharing.error == "Action failed")

        // A successful write still closes its sheet when the subsequent reload fails.
        let succeededWithReloadFailure = await failing.perform {}
        precondition(succeededWithReloadFailure && failing.error == nil && failing.backgroundError != nil)
        print("Sharing model checks passed")
    }
}

private final class SharingModelResponses: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let fails = path.hasPrefix("/failure/")
        let body = path.hasSuffix("preferences") ? #"{"sharedLinks":{"enabled":false}}"# : "[]"
        let response = HTTPURLResponse(url: request.url!, statusCode: fails ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
