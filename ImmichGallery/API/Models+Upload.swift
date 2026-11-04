import Foundation

struct UploadMediaTypes: Decodable, Sendable {
    let image: [String]
    let video: [String]
    let sidecar: [String]
    var extensions: Set<String> { Set((image + video).map { $0.lowercased() }) }
}

struct UploadResponse: Decodable, Sendable {
    let id: String
    let status: String
}

struct UploadCheckResponse: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let id: String
        let action: String
        let assetId: String?
        let isTrashed: Bool?
        let reason: String?
    }
    let results: [Result]
}

struct UploadAlbumResult: Decodable, Sendable {
    let id: String
    let success: Bool
    let error: String?
    let errorMessage: String?
}
