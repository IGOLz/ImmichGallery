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
    }
}

extension AssetGridModel {
    var macOrderedSelection: [String] {
        sections.flatMap { $0.assets ?? [] }.filter { selection.contains($0.id) }.map(\.id)
    }
}

import SwiftUI

extension View {
    func macOriginalDragContainer(model: AssetGridModel, client: ImmichClient) -> some View {
        dragContainer(for: OriginalTransfer.self) { (ids: [String]) in
            ids.map { OriginalTransfer(id: $0, isVideo: model.item($0)?.isVideo ?? false, client: client) }
        }
    }
}
