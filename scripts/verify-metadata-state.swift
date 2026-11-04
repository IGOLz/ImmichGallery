// Offline harness: compile with Models.swift, Models+Metadata.swift and MetadataState.swift.
import Foundation

// Only the snapshot type is needed by this state-only harness.
struct AssetItem {}

enum ImmichError: Error { case http(Int, String) }

@MainActor final class MetadataTestClient {
    var assets: [String: AssetResponse] = [:]
    var edits: [MetadataEdit] = []
    var saved: [MetadataUpdate] = []
    var editWrites = 0
    var editsError: Error?
    var assetReads = 0

    func asset(_ id: String) async throws -> AssetResponse {
        assetReads += 1
        guard let asset = assets[id] else { throw ImmichError.http(404, "Asset not found") }
        return asset
    }
    func metadataEdits(_ id: String) async throws -> MetadataEdits {
        if let editsError { throw editsError }
        return MetadataEdits(edits: edits)
    }
    func updateMetadata(_ update: MetadataUpdate) async throws { saved.append(update) }
    func saveMetadataEdits(_ id: String, edits: [MetadataEdit]) async throws {
        editWrites += 1
        self.edits = edits
    }
}

@MainActor final class MetadataTestPipeline {
    var clears = 0
    var evicted: [String] = []
    func evict(ids: [String]) { clears += 1; evicted += ids }
}

@MainActor final class LibrarySession {
    let client = MetadataTestClient()
    let pipeline = MetadataTestPipeline()
    let user: User? = User(id: "me", email: "", name: "")
    var invalidations = 0
    func invalidateGrids() { invalidations += 1 }
    func handle(_ error: Error) {}
}

@main struct VerifyMetadataState {
    @MainActor static func main() async throws {
        let session = LibrarySession()
        let sharedState = MetadataSharedState()
        let state = MetadataState(shared: sharedState)
        let secondWindow = MetadataState(shared: sharedState)
        state.present(.location, ids: ["own"])
        assert(secondWindow.presentation == nil)
        var exif = Exif()
        exif.exifImageWidth = 192
        exif.exifImageHeight = 128
        let own = AssetResponse(id: "own", ownerId: "me", type: .image, originalFileName: "photo.jpg",
                                fileCreatedAt: "", localDateTime: "", isFavorite: false, isTrashed: false, exifInfo: exif)
        var shared = own
        shared.ownerId = "other"
        session.client.assets = ["own": own, "shared": shared]
        let updated = await state.update(.init(ids: ["own", "shared"], description: "saved"), session: session)
        assert(updated && session.client.saved.last?.ids == ["own"])
        assert(state.error?.contains("Skipped 1") == true)
        assert(state.revision == 1 && state.gridRevision == 0 && state.imageRevision == 0)
        assert(session.invalidations == 0)
        state.busy = true
        let queued = Task { await state.update(.init(ids: ["own"], rating: 4), session: session) }
        try await Task.sleep(for: .milliseconds(100))
        assert(session.client.saved.count == 1)
        state.busy = false
        let queuedResult = await queued.value
        assert(queuedResult && session.client.saved.last?.rating == 4)
        assert(state.gridRevision == 0)
        let dateUpdated = await state.update(.init(ids: ["own"], dateTimeRelative: 30), session: session)
        assert(dateUpdated && state.gridRevision == 1 && session.invalidations == 1)
        let unchanged = await state.saveEdits("own", edits: [], session: session)
        assert(unchanged && session.client.editWrites == 0 && state.imageRevision == 0)
        let rotation = MetadataEdit(action: "rotate", parameters: .init(angle: 90))
        let started = Date()
        let edited = await state.saveEdits("own", edits: [rotation], session: session)
        assert(edited && session.client.editWrites == 1 && state.imageRevision == 1)
        assert(Date().timeIntervalSince(started) < 5 && !state.busy)
        assert(state.error?.contains("processing") != true)
        assert(session.pipeline.clears == 1 && session.pipeline.evicted == ["own"] && state.gridRevision == 2)
        assert(secondWindow.imageRevision == 1 && secondWindow.gridRevision == 2)
        session.client.editsError = ImmichError.http(404, "Missing")
        do { _ = try await state.loadEdits("missing", session: session) } catch {}
        assert(!state.unavailableEdits)
        do { _ = try await state.loadEdits("own", session: session) } catch {}
        assert(state.unavailableEdits)
        state.error = nil
        session.client.editsError = CancellationError()
        let cancelled = await state.saveEdits("own", edits: [], session: session)
        assert(!cancelled && state.error == nil && !state.busy)
        print("Metadata state checks passed: ownership, refresh scope, no-op, bounded wait, 404, cancellation")
    }
}
