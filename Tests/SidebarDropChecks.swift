// swiftc -swift-version 6 ImmichGallery/App/SidebarLayout.swift ImmichGallery/Views/SidebarInsertionDrop.swift Tests/SidebarDropChecks.swift -o build/check-sidebar-drop && build/check-sidebar-drop
import SwiftUI

@main struct SidebarDropChecks {
    static func main() {
        let header = SidebarDropTarget(sectionID: "photos")
        let library = SidebarDropTarget(sectionID: "photos", link: .library)
        let favorites = SidebarDropTarget(sectionID: "photos", link: .favorites)
        let explore = SidebarDropTarget(sectionID: "explore")
        let map = SidebarDropTarget(sectionID: "explore", link: .map)
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 400)
        let frames = [header: CGRect(x: 10, y: 10, width: 190, height: 20),
                      library: CGRect(x: 10, y: 30, width: 190, height: 32),
                      favorites: CGRect(x: 10, y: 62, width: 190, height: 32),
                      explore: CGRect(x: 10, y: 110, width: 190, height: 20),
                      map: CGRect(x: 10, y: 130, width: 190, height: 32)]
        func resolve(_ x: CGFloat, _ y: CGFloat) -> SidebarDropPosition? {
            SidebarDropPosition.resolve(at: CGPoint(x: x, y: y), in: bounds, targets: frames)
        }
        precondition(resolve(20, 32) == SidebarDropPosition(target: header, edge: .after))
        precondition(resolve(20, 60) == SidebarDropPosition(target: library, edge: .after))
        precondition(resolve(195, 32) == resolve(20, 32), "The entire row must accept the drag")
        precondition(resolve(20, 20)?.target == header)
        precondition(resolve(20, 115)?.target == explore)
        precondition(resolve(20, 145) == SidebarDropPosition(target: explore, edge: .after))
        precondition(resolve(20, 99)?.target == favorites, "Gaps resolve to their nearest insertion boundary")
        precondition(resolve(-1, 40) == nil)
        precondition(resolve(221, 40) == nil)
        precondition(resolve(20, -1) == nil)
        precondition(resolve(20, 401) == nil, "Releasing outside the sidebar must cancel the move")
        precondition(SidebarDropPosition.resolve(at: .zero, in: bounds, targets: [:]) == nil)
        precondition(SidebarDropPosition.resolve(at: CGPoint(x: 10, y: 10), in: bounds, targets: [library: .zero]) == nil)
        var scrolled = frames
        scrolled[library] = CGRect(x: 10, y: -50, width: 190, height: 32)
        precondition(SidebarDropPosition.resolve(at: CGPoint(x: 20, y: 32), in: bounds, targets: scrolled)?.target != library)
        // Both halves of one gap must resolve to the same slot and draw at its exact midpoint.
        for gap: CGFloat in [0, 4, 12] {
            let rows = [library: CGRect(x: 10, y: 30, width: 190, height: 32),
                        favorites: CGRect(x: 10, y: 62 + gap, width: 190, height: 40)]
            let fromAbove = SidebarDropPosition.resolve(at: CGPoint(x: 50, y: 58), in: bounds, targets: rows)!
            let fromBelow = SidebarDropPosition.resolve(at: CGPoint(x: 50, y: 65 + gap), in: bounds, targets: rows)!
            precondition(fromAbove == fromBelow, "There is only one insertion slot between two rows")
            precondition(fromAbove.indicatorFrame(in: rows)?.midY == 62 + gap / 2)
            precondition(fromBelow.indicatorFrame(in: rows) == fromAbove.indicatorFrame(in: rows))
            // The visual boundary is identical even for an explicitly constructed before/after pair.
            precondition(SidebarDropPosition(target: favorites, edge: .before).indicatorFrame(in: rows) == fromAbove.indicatorFrame(in: rows))
        }
        precondition(SidebarDropPosition(target: library, edge: .before).indicatorFrame(in: [:]) == nil)
        let beforeLibrary = SidebarDropPosition(target: header, edge: .after)
        let belowFavorites = SidebarDropPosition(target: favorites, edge: .after)
        let lowerSource = CGRect(x: 10, y: 200, width: 190, height: 32)
        precondition(beforeLibrary.landingFrame(for: lowerSource, in: frames)?.minY == 30)
        precondition(belowFavorites.landingFrame(for: frames[library]!, in: frames)?.minY == 62)
        precondition(belowFavorites.landingFrame(for: lowerSource, in: frames)?.minY == 94)
        precondition(belowFavorites.landingFrame(for: lowerSource, in: [:]) == nil)
        print("Sidebar drag checks passed: full rows, one centered slot per gap, full rows, sections, scrolling and outside cancellation")
    }
}
