// Offline hidden-window check. Does not launch or interact with the installed app.
// swiftc -parse-as-library ImmichGallery/Views/Grid/DeferredContextMenu.swift Tests/GridContextMenuChecks.swift -o build/check-grid-context-menu && build/check-grid-context-menu
import AppKit
import SwiftUI

@MainActor @Observable private final class MenuProbe {
    var selected = -1
    @ObservationIgnored var builds = 0
    @ObservationIgnored var appeared: Set<Int> = []
}

private struct MenuGrid: View {
    let probe: MenuProbe
    let deferred: Bool

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                ForEach(0..<10_000) { id in
                    let cell = Rectangle().fill(probe.selected == id ? Color.red : .blue).frame(height: 100)
                        .onAppear { probe.appeared.insert(id) }
                    if deferred {
                        cell.deferredContextMenu { items(id) }
                    } else {
                        cell.contextMenu { items(id) }
                    }
                }
            }
        }
    }

    private func items(_ id: Int) -> some View {
        probe.builds += 1
        return Button(probe.selected == id ? "Selected" : "Select") { probe.selected = id }
    }
}

@main private struct GridContextMenuChecks {
    @MainActor static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var baselineCells: Set<Int> = []
        for deferred in [false, true] {
            let probe = MenuProbe()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: MenuGrid(probe: probe, deferred: deferred))
            window.contentView = host
            settle(host)
            for selection in [0, 1, -1] {
                probe.selected = selection
                settle(host)
            }
            precondition(!probe.appeared.isEmpty, "The probe must display cells in both runs")
            if deferred {
                precondition(probe.appeared == baselineCells, "Both runs must exercise the same cells")
                precondition(probe.builds == 0, "Grid creation and selection changes must not build unopened menus")
            } else {
                baselineCells = probe.appeared
                precondition(probe.builds > 0, "Baseline must reproduce eager menu construction")
            }
            print("\(deferred ? "Deferred" : "Baseline") menu builds: \(probe.builds)")
            window.orderOut(nil)
        }
        print("Grid context menu checks passed")
    }
}
