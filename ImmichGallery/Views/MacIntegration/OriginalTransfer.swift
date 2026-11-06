import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct OriginalTransfer: Transferable, Identifiable, Sendable {
    let id: String
    var isVideo = false
    let client: ImmichClient

    static var transferRepresentation: some TransferRepresentation {
        // The timeline has no filename/type metadata. Advertise a file rather than mislabel RAW/HEIC.
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try await item.client.macIntegrationOriginal(item.id), allowAccessingOriginalFile: true)
        }
        ProxyRepresentation(exporting: { _ in OriginalDragMarker() })
    }
}

extension AssetGridModel {
    var macOrderedSelection: [String] {
        sections.flatMap { $0.assets ?? [] }.filter { selection.contains($0.id) }.map(\.id)
    }
}
