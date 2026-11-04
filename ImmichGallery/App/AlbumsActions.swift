import Foundation
import Observation

@MainActor @Observable
final class AlbumsActions {
    var revision = 0
    var details: [String: AlbumDetails] = [:]
    var creating = false
    var initialAssetIDs: [String] = []
    var error: String?

    func newAlbum(ids: [String] = []) {
        initialAssetIDs = ids
        creating = true
    }

    func perform(session: LibrarySession, operation: @escaping () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { session.handle(error); self.error = error.localizedDescription }
            session.invalidateGrids()
            await session.reloadAlbums()
            revision += 1
        }
    }
}

extension GridSource {
    var albumID: String? { if case .album(let id) = self { id } else { nil } }
}
