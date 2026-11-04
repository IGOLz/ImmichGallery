import CoreTransferable
import UniformTypeIdentifiers

/// Internal album drops use data, leaving room for original-file representations.
struct AlbumAssetTransfer: Codable, Transferable {
    let ids: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .albumAssetIDs)
    }
}

extension UTType {
    static let albumAssetIDs = UTType(exportedAs: "dev.igol.ImmichGallery.asset-ids", conformingTo: .data)
}
