// swiftc -swift-version 6 ImmichGallery/Views/Albums/AlbumAssetTransfer.swift ImmichGallery/Views/Upload/UploadDropPolicy.swift Tests/UploadDropChecks.swift -o build/check-upload-drop && build/check-upload-drop
import AppKit
import UniformTypeIdentifiers

@main struct UploadDropChecks {
    static func main() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let file = NSItemProvider(contentsOf: URL(fileURLWithPath: "/tmp/external.jpg")) ?? NSItemProvider()
        file.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { _ in
            fatalError("Validation must never load or download file contents")
        }
        precondition(!UploadDropPolicy.isInternal([file], pasteboard: pasteboard), "Finder files remain eligible")
        for marker in [UTType.albumAssetIDs, UTType.immichOriginalDrag] {
            let internalFile = NSItemProvider()
            internalFile.registerDataRepresentation(forTypeIdentifier: marker.identifier, visibility: .all) { _ in
                fatalError("Validation only inspects advertised types")
            }
            precondition(UploadDropPolicy.isInternal([internalFile], pasteboard: pasteboard))
            precondition(UploadDropPolicy.isInternal([file, internalFile], pasteboard: pasteboard), "Reject the entire internal drag")
            pasteboard.declareTypes([NSPasteboard.PasteboardType(marker.identifier.lowercased())], owner: nil)
            precondition(UploadDropPolicy.isInternal([file], pasteboard: pasteboard), "File-only providers still expose the marker on the pasteboard")
            pasteboard.clearContents()
            precondition(!UploadDropPolicy.isInternal([file], pasteboard: pasteboard), "A subsequent external drag remains eligible")
        }
        print("Upload drop checks passed: grid/viewer markers, lowercase pasteboard fallback, external files, no content loading")
    }
}
