import Foundation

// Compile with Models.swift and Models+Assets.swift, then pass a directory of captured API JSON responses.
@main struct AssetsDTOCheck {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        func decode<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(contentsOf: directory.appendingPathComponent(file + ".json")))
        }
        let duplicates = try decode([AssetsDuplicate].self, "duplicates")
        let large = try decode([AssetResponse].self, "large")
        let downloads = try decode(AssetsDownloadInfo.self, "download")
        let preferences = try decode(AssetsPreferences.self, "preferences")
        let config = try decode(AssetsServerConfig.self, "config")
        _ = try decode(AssetsCapabilities.self, "features")
        assert(preferences.download.archiveSize > 0)
        assert(downloads.archives.allSatisfy { !$0.assetIds.isEmpty })
        assert(config.trashDays == nil || config.trashDays! >= 0)
        // The stack response embeds the same full asset DTO used by search and duplicates.
        if let asset = large.first {
            let response = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("large.json"))) as! [[String: Any]]
            let stackJSON = try JSONSerialization.data(withJSONObject: ["id": "stack", "primaryAssetId": asset.id, "assets": [response[0]]])
            let stack = try JSONDecoder().decode(AssetsStack.self, from: stackJSON)
            assert(stack.assets.first?.id == stack.primaryAssetId)
        }
        let older = try JSONDecoder().decode(AssetsDuplicate.self, from: Data(#"{"duplicateId":"older","assets":[]}"#.utf8))
        assert(older.suggestedKeepAssetIds == nil)
        print("Decoded \(duplicates.count) duplicate groups, \(large.count) large files, \(downloads.archives.count) archive plans; older-server optional fields passed.")
    }
}
