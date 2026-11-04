import Foundation

struct AssetsStackSummary: Decodable, Sendable {
    let id: String
    let primaryAssetId: String
    let assetCount: Int
}

struct AssetsStack: Decodable, Sendable {
    let id: String
    let primaryAssetId: String
    let assets: [AssetResponse]
}

struct AssetsDuplicate: Decodable, Identifiable, Sendable {
    let duplicateId: String
    let assets: [AssetResponse]
    let suggestedKeepAssetIds: [String]?
    var id: String { duplicateId }
}

struct AssetsDownloadInfo: Decodable, Sendable {
    struct Archive: Decodable, Sendable {
        let assetIds: [String]
        let size: Int64
    }
    let archives: [Archive]
    let totalSize: Int64
}

struct AssetsPreferences: Decodable, Sendable {
    struct Download: Decodable, Sendable {
        let archiveSize: Int64
        let includeEmbeddedVideos: Bool?
    }
    let download: Download
}

struct AssetsCapabilities: Decodable, Sendable { let duplicateDetection: Bool? }
struct AssetsServerConfig: Decodable, Sendable { let trashDays: Int? }
struct AssetsBulkResult: Decodable, Sendable {
    let id: String
    let success: Bool
    let error: String?
}

// Coordinate fields accept either decimal separator, without grouping separators.
enum AssetsCoordinates {
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
}
