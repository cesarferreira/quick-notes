import AppKit

enum NoteHistoryDirection { case older, newer }

struct NoteSwipeGesture {
    struct Result {
        var handled = false
        var direction: NoteHistoryDirection?
    }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis: Axis = .undecided
    private var tracking = false
    private var horizontalMomentum = false
    private var totalX: CGFloat = 0
    private var totalY: CGFloat = 0

    mutating func update(x: CGFloat, y: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase, inverted: Bool) -> Result {
        guard momentum.isEmpty else { return Result(handled: horizontalMomentum) }
        if phase.contains(.began) {
            tracking = true
            horizontalMomentum = false
            totalX = 0
            totalY = 0
            axis = .undecided
        }
        guard tracking else { return Result() }
        if phase.contains(.cancelled) {
            let handled = axis == .horizontal
            tracking = false
            return Result(handled: handled)
        }
        // Normalize to physical swipe direction regardless of natural scrolling.
        totalX += inverted ? -x : x
        totalY += abs(y)
        if axis == .undecided && max(abs(totalX), totalY) >= 10 {
            if abs(totalX) > totalY * 1.5 { axis = .horizontal }
            else if totalY > abs(totalX) { axis = .vertical }
        }
        if axis == .horizontal && totalY > abs(totalX) * 1.5 { axis = .vertical }
        let handled = axis == .horizontal
        if phase.contains(.ended) {
            tracking = false
            horizontalMomentum = handled
            if handled && abs(totalX) >= 60 {
                return Result(handled: true, direction: totalX > 0 ? .older : .newer)
            }
        }
        return Result(handled: handled)
    }
}

final class NotesScrollView: NSScrollView {
    var onNavigate: ((NoteHistoryDirection) -> Void)?
    private var gesture = NoteSwipeGesture()

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }
        let result = gesture.update(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
            phase: event.phase, momentum: event.momentumPhase, inverted: event.isDirectionInvertedFromDevice)
        if let direction = result.direction { onNavigate?(direction) }
        if !result.handled { super.scrollWheel(with: event) }
    }

    override func swipe(with event: NSEvent) {
        if abs(event.deltaX) > abs(event.deltaY) {
            onNavigate?(event.deltaX > 0 ? .older : .newer)
        } else {
            super.swipe(with: event)
        }
    }
}
