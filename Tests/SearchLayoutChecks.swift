// Offline, hidden-window layout regression. No app, credentials or server access.
// swiftc -parse-as-library ImmichGallery/Views/Grid/GridHeaderLayout.swift Tests/SearchLayoutChecks.swift -o build/check-search-layout && build/check-search-layout
import AppKit
import SwiftUI

@MainActor @Observable private final class LayoutState {
    var headerHeight: CGFloat = 52
    var inspector = false
    var headerFrame: CGRect = .zero
    var firstCellFrame: CGRect = .zero
}

private struct SearchLayoutProbe: View {
    @Bindable var state: LayoutState
    let reproduceOldLayout: Bool

    private var header: some View {
        Text("Search controls")
            .frame(maxWidth: .infinity).frame(height: state.headerHeight)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.headerFrame = $0 }
    }

    private var grid: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                    ForEach(0..<100) { i in
                        Color.blue.frame(height: 170)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                if i == 0 { state.firstCellFrame = $0 }
                            }
                    }
                }
            }
        }
        .toolbar { Button("Grid tools") {} }
    }

    var body: some View {
        NavigationSplitView { Text("Sidebar") } detail: {
            NavigationStack {
                Group {
                    if reproduceOldLayout {
                        grid.inspector(isPresented: $state.inspector) { Text("Inspector") }
                            .safeAreaInset(edge: .top, spacing: 0) { header }
                    } else {
                        grid.gridHeader(header)
                            .inspector(isPresented: $state.inspector) { Text("Inspector") }
                    }
                }
                .navigationTitle("Search")
            }
        }
    }
}

@main private struct SearchLayoutChecks {
    @MainActor static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for oldLayout in [true, false] {
            let state = LayoutState()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                                  styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: SearchLayoutProbe(state: state, reproduceOldLayout: oldLayout))
            window.contentView = host
            settle(host)
            if oldLayout {
                if #available(macOS 26, *) {
                    precondition(state.firstCellFrame.minY < state.headerFrame.maxY,
                                 "Regression fixture must reproduce the first row behind the controls")
                }
            } else {
                for inspector in [false, true, false] {
                    state.inspector = inspector
                    for height: CGFloat in [52, 96, 132, 52] {
                        state.headerHeight = height
                        settle(host)
                        precondition(state.firstCellFrame.width > 0)
                        precondition(abs(state.firstCellFrame.minY - state.headerFrame.maxY) < 1,
                                     "First row must start below controls, including chips and inspector")
                        precondition(abs(state.firstCellFrame.minX - state.headerFrame.minX) < 1,
                                     "First column must remain visible beside the sidebar")
                    }
                }
            }
            window.orderOut(nil)
        }
        print("Search layout checks passed: old overlap reproduced; fixed first row, changing header heights and inspector")
    }
}
