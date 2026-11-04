// Offline URLProtocol checks. No requests leave this process.
// Compile with API/*.swift and Support/ImagePipeline.swift.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private final class Responses: @unchecked Sendable {
    let lock = NSLock()
    var thumbnailRequests = 0
    var fallback = false
    var merges: [(String, [String])] = []
    let old = png(size: 1)
    let new = png(size: 2)

    static func png(size: Int) -> Data {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        assert(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class PeopleProtocol: URLProtocol, @unchecked Sendable {
    static let responses = Responses()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, data): (Int, Data) = Self.responses.lock.withLock {
            let state = Self.responses
            if request.url!.path.hasSuffix("/thumbnail") {
                state.thumbnailRequests += 1
                return (200, state.thumbnailRequests < 3 ? state.old : state.new)
            }
            var bodyData = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    assert(count >= 0)
                    if count == 0 { break }
                    bodyData.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            state.merges.append((request.url!.path, body["ids"] as! [String]))
            return (state.fallback && request.url!.path == "/api/people/merge" ? 404 : 200, Data("[]".utf8))
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: data)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PeopleNetworkChecks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PeopleProtocol.self]
        config.urlCache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0)
        let url = URL(string: "https://demo.immich.app")!
        let client = ImmichClient(serverURL: url, apiURL: url.appendingPathComponent("api"), credential: nil,
                                  session: URLSession(configuration: config))
        let pipeline = ImagePipeline(client: client)
        let first = await pipeline.personThumbnail("created-person")
        assert(first?.width == 1)
        _ = await pipeline.personThumbnail("created-person")
        assert(PeopleProtocol.responses.lock.withLock { PeopleProtocol.responses.thumbnailRequests } == 1)
        await pipeline.refreshPersonThumbnail("created-person", replacing: PeopleProtocol.responses.old)
        let refreshed = await pipeline.personThumbnail("created-person")
        assert(refreshed?.width == 2)
        assert(PeopleProtocol.responses.lock.withLock { PeopleProtocol.responses.thumbnailRequests } == 3)
        pipeline.invalidatePerson("created-person")
        _ = await pipeline.personThumbnail("created-person")
        assert(PeopleProtocol.responses.lock.withLock { PeopleProtocol.responses.thumbnailRequests } == 4)

        try await client.mergePeople(into: "target", ids: ["source"])
        PeopleProtocol.responses.lock.withLock { PeopleProtocol.responses.fallback = true }
        try await client.mergePeople(into: "target", ids: ["source"])
        let merges = PeopleProtocol.responses.lock.withLock { PeopleProtocol.responses.merges }
        assert(merges.count == 3)
        assert(merges[0].0 == "/api/people/merge" && merges[0].1 == ["target", "source"])
        assert(merges[1].0 == "/api/people/merge" && merges[1].1 == ["target", "source"])
        assert(merges[2].0 == "/api/people/target/merge" && merges[2].1 == ["source"])
        print("Offline thumbnail cache, delayed refresh and merge fallback checks passed.")
    }
}
