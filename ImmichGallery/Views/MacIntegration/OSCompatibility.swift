import CoreTransferable
import SwiftUI

// macOS 15 fallbacks for the few macOS 26 APIs the app uses.
// On macOS 26+ every helper calls the original API, so behavior there is unchanged.

extension View {
    /// Liquid Glass on macOS 26+, a regular material on earlier systems.
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Multi-item drag of the grid selection to the Finder. macOS 26+ only;
    /// on earlier systems each cell drags its own item (see `LegacyAssetDrag`).
    @ViewBuilder
    func macOriginalDragContainer(model: AssetGridModel, client: ImmichClient) -> some View {
        if #available(macOS 26, *) {
            dragContainer(for: OriginalTransfer.self) { (ids: [String]) in
                ids.map { OriginalTransfer(id: $0, isVideo: model.item($0)?.isVideo ?? false, client: client) }
            }
            .dragContainerSelection(Array(model.selection))
        } else {
            self
        }
    }

    /// Per-item original drag that joins the drag container on macOS 26+. No-op earlier.
    @ViewBuilder
    func macOriginalContainerItem(_ item: OriginalTransfer?) -> some View {
        if #available(macOS 26, *) {
            draggable(OriginalTransfer.self, item: item)
        } else {
            self
        }
    }

    /// Standalone original drag (no container). Both branches keep a stable view
    /// identity when `isEnabled` flips, so zooming doesn't recreate the view.
    @ViewBuilder
    func macOriginalDraggable(_ item: OriginalTransfer, isEnabled: Bool) -> some View {
        if #available(macOS 26, *) {
            draggable(OriginalTransfer.self, item: isEnabled ? item : nil)
        } else {
            // Parent gestures use their own content shape, so they still get events.
            draggable(item).allowsHitTesting(isEnabled)
        }
    }
}

/// macOS 15 grid drag: one item that both album drop targets (asset IDs)
/// and the Finder (the original file of the dragged photo) understand.
struct LegacyAssetDrag: Transferable {
    let album: AlbumAssetTransfer
    let original: OriginalTransfer

    static var transferRepresentation: some TransferRepresentation {
        // Original first, so the Finder takes the file rather than the ID payload.
        ProxyRepresentation(exporting: \.original)
        ProxyRepresentation(exporting: \.album)
    }
}

import MapKit

extension MKMapItem {
    /// `location` on macOS 26+, the (since deprecated) placemark on earlier systems.
    var adaptiveCoordinate: CLLocationCoordinate2D {
        if #available(macOS 26, *) { location.coordinate } else { placemark.coordinate }
    }
}
