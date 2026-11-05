// swiftc -parse-as-library ImmichGallery/Views/SidebarRowAppearance.swift Tests/SidebarPreviewChecks.swift -o build/check-sidebar-preview && build/check-sidebar-preview
import AppKit
import SwiftUI

@main struct SidebarPreviewChecks {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let state = SidebarDragPreviewState()
        state.frame = CGRect(x: 10, y: 100, width: 190, height: 28)
        let preview = SidebarFloatingPreview(selected: false, state: state) {
            Label("People", systemImage: "person.crop.square")
        }
        let host = NSHostingView(rootView: ZStack(alignment: .topLeading) { preview }
            .frame(width: 220, height: 400).background(.white).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }
        func bluePixels(in rect: CGRect) -> Int {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            var count = 0
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.blueComponent > 0.4, color.blueComponent - color.redComponent > 0.2 { count += 1 }
                }
            }
            return count
        }
        settle()
        precondition(bluePixels(in: state.frame) > 10, "The dragged row icon must be visible at the pointer location")
        let oldFrame = state.frame
        state.frame.origin.y = 200
        settle()
        precondition(bluePixels(in: state.frame) > 10, "The preview must follow observable frame updates")
        precondition(bluePixels(in: oldFrame) == 0, "The preview must leave its previous position")
        window.orderOut(nil)
        print("Sidebar preview checks passed: real row graphics are visible and follow the dragged frame")
    }
}
