import AppKit
import XCTest
import QuickNotesCore
@testable import QuickNotes

final class AnimationTests: XCTestCase {
    private func withController(reduceMotion: @escaping () -> Bool = { false }, _ body: (NotesController, NoteStore) throws -> Void) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore(directory: directory)
        let controller = try NotesController(store: store, motion: NoteMotion(reduceMotion: reduceMotion))
        controller.panel.contentView?.layoutSubtreeIfNeeded()
        defer { controller.panel.orderOut(nil) }
        try body(controller, store)
    }

    private func animations(on layer: CALayer?) -> [CAAnimation] {
        layer?.animationKeys()?.compactMap { layer?.animation(forKey: $0) } ?? []
    }

    func testRevealAnimatesWithoutDelayingKeyboardFocus() throws {
        try withController { controller, _ in
            controller.show()
            let frame = try XCTUnwrap(controller.panel.contentView?.superview?.layer)
            XCTAssertFalse(animations(on: frame).isEmpty, "Opening should have a spring entrance")
            XCTAssertTrue(controller.panel.isKeyWindow)
            XCTAssertTrue(controller.panel.firstResponder === controller.editor)
            controller.editor.insertText("Immediate", replacementRange: controller.editor.selectedRange())
            XCTAssertEqual(controller.editor.string, "Immediate")
        }
    }

    func testFadeSavesImmediatelyAndReopeningCancelsOldDismissal() throws {
        try withController { controller, store in
            controller.show()
            controller.editor.insertText("Keep this", replacementRange: controller.editor.selectedRange())
            controller.hide()
            XCTAssertEqual(try store.load().first?.body, "Keep this")
            XCTAssertTrue(controller.panel.isVisible, "The panel should stay onscreen while fading")
            controller.show()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            XCTAssertTrue(controller.panel.isVisible, "An old fade completion must not dismiss the reopened panel")
            XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
            XCTAssertTrue(controller.panel.firstResponder === controller.editor)
            controller.hide()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            XCTAssertFalse(controller.panel.isVisible)
        }
    }

    func testHistoryCrossfadeFocusesSearchImmediately() throws {
        try withController { controller, _ in
            controller.show()
            controller.toggleHistory()
            let content = try XCTUnwrap(controller.editor.enclosingScrollView?.superview)
            XCTAssertTrue(animations(on: content.layer).contains { ($0 as? CATransition)?.type == .fade })
            XCTAssertTrue(controller.panel.firstResponder === controller.search.currentEditor())
            controller.toggleHistory()
            XCTAssertTrue(controller.panel.firstResponder === controller.editor)
        }
    }

    func testCheckingTaskDrawsTickAndStillPreservesSelectionAndUndo() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.insertText("[ ] Ship it", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 11, length: 0))
            editor.undoManager?.removeAllActions()
            editor.insertTask()
            XCTAssertEqual(editor.string, "[x] Ship it")
            XCTAssertEqual(editor.selectedRange().location, 11)
            let shapes = editor.layer?.sublayers?.flatMap { $0.sublayers ?? [] } ?? []
            XCTAssertTrue(shapes.contains { layer in
                animations(on: layer).contains { ($0 as? CABasicAnimation)?.keyPath == "strokeEnd" }
            }, "Checking a task should draw in the tick")
            editor.undoManager?.undo()
            XCTAssertEqual(editor.string, "[ ] Ship it")
        }
    }

    func testReduceMotionSkipsTransitionsAndDismissesImmediately() throws {
        try withController(reduceMotion: { true }) { controller, _ in
            controller.show()
            XCTAssertTrue(animations(on: controller.panel.contentView?.superview?.layer).isEmpty)
            XCTAssertEqual(controller.panel.alphaValue, 1)
            controller.toggleHistory()
            XCTAssertTrue(animations(on: controller.editor.enclosingScrollView?.superview?.layer).isEmpty)
            controller.toggleHistory()
            controller.editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            controller.editor.insertTask()
            XCTAssertEqual(controller.editor.string, "[x] Task")
            XCTAssertFalse(controller.editor.layer?.sublayers?.contains { $0.sublayers?.contains { $0 is CAShapeLayer } == true } == true)
            let button = try XCTUnwrap(controller.panel.contentView?.subviews.first?.subviews.compactMap { $0 as? IconButton }.first)
            button.highlight(true)
            XCTAssertTrue(animations(on: button.layer).isEmpty)
            XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(button.layer).transform))
            XCTAssertGreaterThan(button.layer?.backgroundColor?.alpha ?? 0, 0)
            controller.hide()
            XCTAssertFalse(controller.panel.isVisible)
        }
    }

    func testRapidShortcutTogglesEndInTheRequestedVisibility() throws {
        try withController { controller, _ in
            controller.show()
            controller.toggle()
            controller.toggle()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            XCTAssertTrue(controller.panel.isVisible)
            XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
            controller.toggle()
            controller.toggle()
            controller.toggle()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            XCTAssertFalse(controller.panel.isVisible)
        }
    }

    func testSwipeDirectionChangesButEditingAndSavingStayImmediate() throws {
        try withController { controller, store in
            let older = Note(body: "Older")
            try store.save(older, expectedBody: nil)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: store.url(for: older).path)
            controller.newNote()
            controller.editor.insertText("Newest", replacementRange: NSRange(location: 0, length: 0))
            let newestID = controller.current.id
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.editor.string, "Older")
            XCTAssertEqual(try store.load().first(where: { $0.id == newestID })?.body, "Newest")
            let scroll = try XCTUnwrap(controller.editor.enclosingScrollView)
            XCTAssertEqual(animations(on: scroll.layer).compactMap { $0 as? CATransition }.first?.subtype, .fromRight)
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.editor.string, "Newest")
            XCTAssertEqual(animations(on: scroll.layer).compactMap { $0 as? CATransition }.first?.subtype, .fromLeft)
            controller.editor.insertText(" now", replacementRange: controller.editor.selectedRange())
            XCTAssertEqual(controller.editor.string, "Newest now")
        }
    }

    func testTypingCancelsTheCheckboxOverlaySoItCannotCoverAnotherLine() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            editor.insertTask()
            XCTAssertTrue(editor.layer?.sublayers?.contains { $0.sublayers?.contains { $0 is CAShapeLayer } == true } == true)
            editor.insertText(" now", replacementRange: editor.selectedRange())
            XCTAssertFalse(editor.layer?.sublayers?.contains { $0.sublayers?.contains { $0 is CAShapeLayer } == true } == true)
            XCTAssertEqual(editor.string, "[x] Task now")
        }
    }

    func testToolbarHoverAndPressFeedbackLeaveTheButtonUsable() throws {
        try withController { controller, _ in
            let button = try XCTUnwrap(controller.panel.contentView?.subviews.first?.subviews.compactMap { $0 as? IconButton }.first)
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
            button.mouseEntered(with: event)
            let layer = try XCTUnwrap(button.layer)
            XCTAssertGreaterThan(layer.backgroundColor?.alpha ?? 0, 0)
            button.highlight(true)
            XCTAssertFalse(CATransform3DIsIdentity(layer.transform))
            button.highlight(false)
            button.mouseExited(with: event)
            XCTAssertTrue(CATransform3DIsIdentity(layer.transform))
            XCTAssertEqual(layer.backgroundColor?.alpha ?? 0, 0)
            XCTAssertTrue(button.isEnabled)
        }
    }

    func testSourceModeDoesNotOverlayRawMarkdownWhenTogglingTask() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.sourceMode = true
            editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            editor.insertTask()
            XCTAssertEqual(editor.string, "[x] Task")
            XCTAssertFalse(editor.layer?.sublayers?.contains { $0.sublayers?.contains { $0 is CAShapeLayer } == true } == true)
        }
    }

    func testFailedSaveDoesNotStartAFadeOrDismissTheDraft() throws {
        try withController { controller, store in
            controller.show()
            controller.editor.insertText("Unsaved", replacementRange: NSRange(location: 0, length: 0))
            try FileManager.default.removeItem(at: store.directory)
            try Data().write(to: store.directory)
            controller.hide()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            XCTAssertTrue(controller.panel.isVisible)
            XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
            XCTAssertEqual(controller.editor.string, "Unsaved")
        }
    }
}
