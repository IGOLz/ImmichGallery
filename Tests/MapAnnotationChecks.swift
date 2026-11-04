import Foundation
import SwiftUI

/// Renders MapKit's content without any custom environment, window, or app lifecycle.
@main struct MapAnnotationChecks {
    @MainActor static func main() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoNetworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://example.invalid/api")!
        let pipeline = ImagePipeline(client: ImmichClient(serverURL: url, apiURL: url, credential: .accessToken("offline"), session: session))
        for count in [0, 1, 2, 50] {
            let cluster = ExploreMapCluster(id: "test", lat: 0, lon: 0, assets: (0..<count).map(String.init), bbox: "0,0,1,1")
            let renderer = ImageRenderer(content: ExploreMapAnnotation(cluster: cluster, pipeline: pipeline, select: {}).padding(8))
            precondition(renderer.cgImage != nil, "Annotation must render without LibrarySession or AppModel")
        }
        print("Map annotation checks passed: empty/single/multiple thumbnails render without custom environment or network")
    }
}

private final class NoNetworkProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { preconditionFailure("Annotation rendering must not make network requests") }
    override func stopLoading() {}
}
