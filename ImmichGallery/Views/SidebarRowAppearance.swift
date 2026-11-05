import SwiftUI

struct SidebarRowContent<Content: View>: View {
    let selected: Bool
    let active: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .labelStyle(SidebarRowLabelStyle(selected: selected, active: active))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selected ? Color(nsColor: active ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct SidebarRowLabelStyle: LabelStyle {
    let selected: Bool
    let active: Bool
    private var selectedText: Color { Color(nsColor: active ? .alternateSelectedControlTextColor : .unemphasizedSelectedTextColor) }
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(selected ? selectedText : Color.accentColor).frame(width: 20)
            configuration.title.foregroundStyle(selected ? selectedText : Color.primary).lineLimit(1)
        }
    }
}

@MainActor @Observable final class SidebarDragPreviewState {
    var frame = CGRect.zero
}

struct SidebarFloatingPreview<Content: View>: View {
    let selected: Bool
    let state: SidebarDragPreviewState
    @ViewBuilder let content: Content
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        SidebarRowContent(selected: selected, active: activeState == .key) { content }
            .frame(width: state.frame.width, height: state.frame.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .position(x: state.frame.midX, y: state.frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
