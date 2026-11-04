// swiftc ImmichGallery/API/Models.swift ImmichGallery/API/Models+Metadata.swift scripts/verify-metadata.swift -o /tmp/verify-metadata
// /tmp/verify-metadata [preferences.json asset.json edits.json]
import Foundation

@main
struct VerifyMetadata {
    static func main() throws {
        var exif = Exif()
        exif.exifImageWidth = 192
        exif.exifImageHeight = 128
        exif.orientation = "6"
        assert(exif.metadataDimensions?.width == 128 && exif.metadataDimensions?.height == 192)
        exif.orientation = "1"
        assert(exif.metadataDimensions?.width == 192 && exif.metadataDimensions?.height == 128)
        let encoder = JSONEncoder()
        func object(_ update: MetadataUpdate) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(update)) as! [String: Any]
        }
        let omitted = try object(.init(ids: ["test"], description: ""))
        assert(omitted["rating"] == nil)
        assert(omitted["description"] as? String == "")
        let cleared = try object(.init(ids: ["test"], clearRating: true))
        assert(cleared["rating"] is NSNull)
        let relative = try object(.init(ids: ["a", "b"], dateTimeRelative: -90, timeZone: "Europe/Rome"))
        assert(relative["dateTimeRelative"] as? Int == -90)
        assert(relative["dateTimeOriginal"] == nil)
        assert(relative["timeZone"] as? String == "Europe/Rome")
        let crop = MetadataEdit(action: "crop", parameters: .init(x: 10, y: 20, width: 100, height: 80))
        let rotation = MetadataEdit(action: "rotate", parameters: .init(angle: 270))
        let edits = MetadataEdits(edits: [crop, rotation])
        let decoded = try JSONDecoder().decode(MetadataEdits.self, from: encoder.encode(edits))
        assert(decoded.edits[0].parameters.width == 100 && decoded.edits[1].parameters.angle == 270)
        if CommandLine.arguments.count == 4 {
            let decoder = JSONDecoder()
            let preferences = try decoder.decode(MetadataPreferences.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let asset = try decoder.decode(AssetResponse.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
            let liveEdits = try decoder.decode(MetadataEdits.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
            print("Live DTO decode passed: ratings enabled=\(preferences.ratings?.enabled ?? false), asset=\(asset.id), edits=\(liveEdits.edits.count)")
        }
        print("Metadata encoding checks passed")
    }
}
