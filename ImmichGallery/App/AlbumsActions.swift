import Foundation
import Observation

@MainActor @Observable
final class AlbumsActions {
    var revisions: [String: Int] = [:]
    var navigationAlbumID: String?
    @ObservationIgnored private weak var selectionModel: AssetGridModel?
    var details: [String: AlbumDetails] = [:]
    var creating = false
    var initialAssetIDs: [String] = []
    var error: String?

    func newAlbum(ids: [String] = [], model: AssetGridModel? = nil) {
        selectionModel = model
        initialAssetIDs = ids
        creating = true
    }

    func didCreate(_ albumID: String) {
        selectionModel?.selection = []
        selectionModel = nil
        navigationAlbumID = albumID
    }

    func perform(session: LibrarySession, albumID: String, reloadTimeline: Bool = true, operation: @escaping () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { session.handle(error); self.error = error.localizedDescription }
            if reloadTimeline {
                session.invalidateAlbumGrid(albumID)
                revisions[albumID, default: 0] += 1
            }
            await session.reloadAlbums()
        }
    }
}

extension GridSource {
    var albumID: String? { if case .album(let id) = self { id } else { nil } }
}
