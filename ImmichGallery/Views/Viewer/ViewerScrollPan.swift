import AppKit
import SwiftUI

/// Two-finger trackpad movement arrives as scroll events, not a SwiftUI drag.
struct ViewerScrollPan: NSViewRepresentable {
    let isEnabled: Bool
    let onScroll: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollPanView { ScrollPanView() }

    func updateNSView(_ view: ScrollPanView, context: Context) {
        view.isEnabled = isEnabled
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: ScrollPanView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ScrollPanView: NSView {
        var isEnabled = false
        var onScroll: ((CGSize) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event)
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard isEnabled, let window, event.window === window,
                  visibleRect.contains(convert(event.locationInWindow, from: nil))
            else { return event }
            onScroll?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            return nil
        }
    }
}
