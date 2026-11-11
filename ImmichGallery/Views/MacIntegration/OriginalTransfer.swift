import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The single drag payload of a grid or viewer asset. Outside the app it is only the original
/// file; the marker and album asset IDs follow it for the app's own drop targets.
struct OriginalTransfer: Transferable, Identifiable, Sendable {
    let id: String
    var isVideo = false
    let client: ImmichClient
    /// Asset IDs for album drops. `nil` (Locked Folder, viewer) exports no album representation.
    var albumIDs: [String]? = nil

    static var transferRepresentation: some TransferRepresentation {
        // The original first: the Finder saves the first representation it can.
        // The timeline has no filename/type metadata. Advertise a file rather than mislabel RAW/HEIC.
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try await item.client.macIntegrationOriginal(item.id), allowAccessingOriginalFile: true)
        }
        ProxyRepresentation(exporting: { _ in OriginalDragMarker() })
        ProxyRepresentation(exporting: { item in AlbumAssetTransfer(ids: item.albumIDs ?? []) })
            .exportingCondition { $0.albumIDs != nil }
    }
}
