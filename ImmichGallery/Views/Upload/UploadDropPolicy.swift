import AppKit
import CoreTransferable
import UniformTypeIdentifiers

/// Marks original-file drags without changing their file representation or album selection.
struct OriginalDragMarker: Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .immichOriginalDrag)
    }
}

extension UTType {
    static let immichOriginalDrag = UTType(exportedAs: "dev.igol.ImmichGallery.original-drag", conformingTo: .data)
}

enum UploadDropPolicy {
    static func isInternal(_ providers: [NSItemProvider], pasteboard: NSPasteboard = NSPasteboard(name: .drag)) -> Bool {
        // AppKit can lowercase custom types on the drag pasteboard.
        let internalTypes = Set([UTType.immichOriginalDrag.identifier.lowercased(), UTType.albumAssetIDs.identifier.lowercased()])
        let types = providers.flatMap(\.registeredTypeIdentifiers) + (pasteboard.types ?? []).map(\.rawValue)
        return types.contains { internalTypes.contains($0.lowercased()) }
    }
}
