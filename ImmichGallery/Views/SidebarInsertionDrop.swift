import SwiftUI

struct SidebarDropTarget: Hashable {
    let sectionID: String
    var link: SidebarLink?
}

struct SidebarDropPosition: Equatable {
    let target: SidebarDropTarget
    let edge: SidebarInsertionEdge

    static func resolve(at point: CGPoint, in bounds: CGRect, targets: [SidebarDropTarget: CGRect]) -> Self? {
        guard bounds.contains(point) else { return nil }
        let visible = targets.filter { $0.value.width > 0 && $0.value.height > 0 && $0.value.intersects(bounds) }
        guard let closest = visible.min(by: {
            let left = distance(point.y, to: $0.value), right = distance(point.y, to: $1.value)
            return left == right ? $0.value.minY < $1.value.minY : left < right
        }) else { return nil }
        let edge = closest.key.link == nil ? .after : SidebarInsertionEdge(locationY: point.y - closest.value.minY, rowHeight: closest.value.height)
        if edge == .before, let previous = visible.filter({
            $0.key.sectionID == closest.key.sectionID && $0.value.maxY <= closest.value.minY
        }).max(by: { $0.value.maxY < $1.value.maxY }) {
            return Self(target: previous.key, edge: .after)
        }
        return Self(target: closest.key, edge: edge)
    }

    func indicatorFrame(in targets: [SidebarDropTarget: CGRect]) -> CGRect? {
        guard let frame = targets[target] else { return nil }
        let neighbors = targets.filter { $0.key != target && $0.key.sectionID == target.sectionID }
        let centerY: CGFloat
        switch edge {
        case .before:
            let previous = neighbors.values.filter { $0.maxY <= frame.minY }.map(\.maxY).max() ?? frame.minY
            centerY = (previous + frame.minY) / 2
        case .after:
            let next = neighbors.values.filter { $0.minY >= frame.maxY }.map(\.minY).min() ?? frame.maxY
            centerY = (frame.maxY + next) / 2
        }
        return CGRect(x: frame.minX, y: centerY - 3.5, width: frame.width, height: 7)
    }

    func landingFrame(for source: CGRect, in targets: [SidebarDropTarget: CGRect]) -> CGRect? {
        guard let boundary = indicatorFrame(in: targets) else { return nil }
        // Removing a row above the destination shifts that insertion point up by one row.
        let y = boundary.midY - (source.minY < boundary.midY ? source.height : 0)
        return CGRect(x: boundary.minX, y: y, width: source.width, height: source.height)
    }

    private static func distance(_ y: CGFloat, to rect: CGRect) -> CGFloat {
        if y < rect.minY { return rect.minY - y }
        if y > rect.maxY { return y - rect.maxY }
        return 0
    }
}

struct SidebarDropRegion: ViewModifier {
    let target: SidebarDropTarget
    @Binding var frames: [SidebarDropTarget: CGRect]

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("sidebarDrag")) } action: { frames[target] = $0 }
            .onDisappear { frames.removeValue(forKey: target) }
    }
}

struct SidebarInsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(.tint, lineWidth: 2).frame(width: 7, height: 7)
            Rectangle().fill(.tint).frame(height: 2)
        }
        .padding(.horizontal, 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
