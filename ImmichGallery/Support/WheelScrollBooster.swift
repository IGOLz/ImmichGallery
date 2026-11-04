import AppKit
import SwiftUI

enum WheelScroll {
    static let multiplierKey = "wheelScrollMultiplier"
    static let defaultMultiplier = 3.0
}

extension View {
    /// Makes classic mouse wheels scroll faster over this view, the way Photos does.
    /// Trackpads and Magic Mouse send precise deltas and are left untouched.
    func fastWheelScrolling() -> some View {
        background(WheelScrollBooster())
    }
}

private struct WheelScrollBooster: NSViewRepresentable {
    func makeNSView(context: Context) -> BoosterView { BoosterView() }
    func updateNSView(_ nsView: BoosterView, context: Context) {}
}

private final class BoosterView: NSView {
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.boost(event) ?? event
        }
    }

    private func boost(_ event: NSEvent) -> NSEvent {
        let multiplier = UserDefaults.standard.object(forKey: WheelScroll.multiplierKey) as? Double ?? WheelScroll.defaultMultiplier
        guard multiplier != 1,
              !event.hasPreciseScrollingDeltas,
              event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let cg = event.cgEvent?.copy()
        else { return event }

        // Scale the fixed-point (line) and pixel deltas on both axes; AppKit reads these.
        // Don't touch the integer line field: writing it also resets the fixed-point value.
        for (fixed, points) in [
            (CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
        ] {
            let fixedValue = cg.getDoubleValueField(fixed)
            let pointValue = Double(cg.getIntegerValueField(points))
            cg.setDoubleValueField(fixed, value: fixedValue * multiplier)
            cg.setIntegerValueField(points, value: Int64((pointValue * multiplier).rounded()))
        }
        return NSEvent(cgEvent: cg) ?? event
    }
}
