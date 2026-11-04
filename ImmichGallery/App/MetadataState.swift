import Foundation
import Observation

@MainActor @Observable
final class MetadataState {
    struct Presentation: Identifiable {
        enum Kind { case date, location, crop }
        let id = UUID()
        let kind: Kind
        let ids: [String]
    }
    var presentation: Presentation?
    var viewerSnapshot: AssetItem?
    var revision = 0
    var busy = false
    var error: String?
    var unavailableEdits = false

    func present(_ kind: Presentation.Kind, ids: [String]) {
        guard !ids.isEmpty, !busy else { return }
        presentation = Presentation(kind: kind, ids: ids)
    }

    func update(_ update: MetadataUpdate, session: LibrarySession) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await session.client.updateMetadata(update)
            refresh(session)
            return true
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
            return false
        }
    }

    func saveEdits(_ id: String, edits: [MetadataEdit], session: LibrarySession) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let before = try await session.client.asset(id)
            try await session.client.saveMetadataEdits(id, edits: edits)
            // Thumbnail generation is asynchronous, as in the web editor's AssetEditReadyV2 event.
            for _ in 0..<30 {
                try await Task.sleep(for: .seconds(1))
                let after = try await session.client.asset(id)
                if after.thumbhash != before.thumbhash {
                    session.pipeline.removeAll()
                    refresh(session)
                    return true
                }
            }
            session.pipeline.removeAll()
            refresh(session)
            error = "Edits were saved. The server is still processing the image. Use Refresh to check again."
            return true
        } catch {
            if case ImmichError.http(404, _) = error { unavailableEdits = true }
            session.handle(error)
            self.error = error.localizedDescription
            return false
        }
    }

    func rotate(_ id: String, clockwise: Bool, session: LibrarySession) async {
        do {
            var edits = try await session.client.metadataEdits(id).edits
            let angle = edits.filter { $0.action == "rotate" }.reduce(0) { $0 + ($1.parameters.angle ?? 0) }
            edits.removeAll { $0.action == "rotate" }
            let next = (angle + (clockwise ? 90 : 270)) % 360
            if next != 0 { edits.append(MetadataEdit(action: "rotate", parameters: .init(angle: next))) }
            _ = await saveEdits(id, edits: edits, session: session)
        } catch {
            if case ImmichError.http(404, _) = error { unavailableEdits = true }
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func refresh(_ session: LibrarySession) {
        revision += 1
        session.invalidateGrids()
    }
}
