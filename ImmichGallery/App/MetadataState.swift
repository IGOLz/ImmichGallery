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
    var imageRevision = 0
    var gridRevision = 0
    var imageEligibility: [String: Bool] = [:]
    var busy = false
    var error: String?
    var unavailableEdits = false

    func present(_ kind: Presentation.Kind, ids: [String]) {
        guard !ids.isEmpty, !busy else { return }
        presentation = Presentation(kind: kind, ids: ids)
    }

    func update(_ update: MetadataUpdate, session: LibrarySession) async -> Bool {
        // Blur/selection saves must wait for an in-flight rating or image edit.
        while busy {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return false }
        }
        busy = true
        defer { busy = false }
        do {
            var owned = update
            owned.ids = []
            for id in update.ids {
                let asset = try await session.client.asset(id)
                if let userID = session.user?.id, asset.ownerId == userID { owned.ids.append(id) }
            }
            let skipped = update.ids.count - owned.ids.count
            guard !owned.ids.isEmpty else {
                error = String(localized: "Only assets you own can be updated. No items were changed.")
                return false
            }
            try await session.client.updateMetadata(owned)
            refresh(session, reloadGrid: update.dateTimeOriginal != nil || update.dateTimeRelative != nil)
            if skipped > 0 { error = String(localized: "Updated \(owned.ids.count) items. Skipped \(skipped) items you do not own.") }
            return true
        } catch is CancellationError {
            return false
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
            return false
        }
    }

    func checkImageEligibility(_ ids: [String], session: LibrarySession) async {
        guard ids.count == 1 else { return }
        for id in ids {
            guard !Task.isCancelled else { return }
            if let asset = try? await session.client.asset(id) {
                imageEligibility[id] = asset.canEditMetadataImage(userID: session.user?.id)
            }
        }
    }

    /// A missing asset must not disable the editor for the entire session.
    func loadEdits(_ id: String, session: LibrarySession) async throws -> MetadataEdits {
        do { return try await session.client.metadataEdits(id) }
        catch {
            if case ImmichError.http(404, _) = error,
               (try? await session.client.asset(id)) != nil { unavailableEdits = true }
            throw error
        }
    }

    func saveEdits(_ id: String, edits: [MetadataEdit], session: LibrarySession) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let before = try await session.client.asset(id)
            guard before.canEditMetadataImage(userID: session.user?.id) else {
                error = String(localized: "This asset cannot be edited. Only owned, non-panorama still images with dimensions are supported.")
                return false
            }
            let existing = try await loadEdits(id, session: session).edits
            guard existing != edits else { return true }
            try await session.client.saveMetadataEdits(id, edits: edits)
            // A successful edit can preserve the thumbhash. Bound the wait in that case.
            for _ in 0..<3 {
                try await Task.sleep(for: .seconds(1))
                let after = try await session.client.asset(id)
                if after.thumbhash != before.thumbhash { break }
            }
            session.pipeline.removeAll()
            imageRevision += 1
            refresh(session, reloadGrid: true)
            return true
        } catch is CancellationError {
            return false
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
            return false
        }
    }

    func rotate(_ id: String, clockwise: Bool, session: LibrarySession) async {
        do {
            var edits = try await loadEdits(id, session: session).edits
            let angle = edits.filter { $0.action == "rotate" }.reduce(0) { $0 + ($1.parameters.angle ?? 0) }
            edits.removeAll { $0.action == "rotate" }
            let next = (angle + (clockwise ? 90 : 270)) % 360
            if next != 0 { edits.append(MetadataEdit(action: "rotate", parameters: .init(angle: next))) }
            _ = await saveEdits(id, edits: edits, session: session)
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func refresh(_ session: LibrarySession, reloadGrid: Bool) {
        revision += 1
        if reloadGrid {
            gridRevision += 1
            session.invalidateGrids()
        }
    }
}
