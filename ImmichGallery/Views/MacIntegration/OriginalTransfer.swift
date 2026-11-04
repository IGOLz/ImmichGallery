import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct OriginalTransfer: Transferable, Identifiable, Sendable {
    let id: String
    var isVideo = false
    let client: ImmichClient

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .image) { item in
            SentTransferredFile(try await item.client.macIntegrationOriginal(item.id), allowAccessingOriginalFile: false)
        }.exportingCondition { !$0.isVideo }
        FileRepresentation(exportedContentType: .movie) { item in
            SentTransferredFile(try await item.client.macIntegrationOriginal(item.id), allowAccessingOriginalFile: false)
        }.exportingCondition { $0.isVideo }
    }
}
