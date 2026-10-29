import AppKit
import XCTest
import QuickNotesCore
@testable import QuickNotes

final class EditorTests: XCTestCase {
    private func withController(_ body: (NotesController, NoteStore) throws -> Void) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore(directory: directory)
        let controller = try NotesController(store: store)
        controller.panel.contentView?.layoutSubtreeIfNeeded()
        try body(controller, store)
        controller.panel.orderOut(nil)
    }

    func testLiveMarkdownSavesRawSourceAndHistoryReopensIt() throws {
        try withController { controller, store in
            controller.editor.insertText("# Release\n[ ] Ship **today**", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(controller.save())
            XCTAssertEqual(try store.load().first?.body, "# Release\n[ ] Ship **today**")
            let storage = try XCTUnwrap(controller.editor.textStorage)
            let markerFont = try XCTUnwrap(storage.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)
            XCTAssertLessThan(markerFont.pointSize, 1)
            controller.newNote()
            XCTAssertEqual(controller.editor.string, "")
            controller.toggleHistory()
            XCTAssertEqual(controller.numberOfRows(in: controller.table), 1)
            controller.openSelectedNote()
            XCTAssertEqual(controller.editor.string, "# Release\n[ ] Ship **today**")
        }
    }

    func testChecklistClickPreservesCaretAndCanUndo() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.insertText("[ ] Ship it", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 11, length: 0))
            editor.undoManager?.removeAllActions()
            let point = editor.convert(NSPoint(x: editor.textContainerOrigin.x + 8, y: editor.textContainerOrigin.y + 9), to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            editor.mouseDown(with: event)
            XCTAssertEqual(editor.string, "[x] Ship it")
            XCTAssertEqual(editor.selectedRange().location, 11)
            XCTAssertTrue(editor.undoManager?.canUndo == true)
            editor.undoManager?.undo()
            XCTAssertEqual(editor.string, "[ ] Ship it")
        }
    }

    func testTypingReturnAndTabContinuesAndNestsTasks() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.insertText("[ ] Parent", replacementRange: NSRange(location: 0, length: 0))
            editor.insertNewline(nil)
            editor.insertTab(nil)
            editor.insertText("Child", replacementRange: editor.selectedRange())
            XCTAssertEqual(editor.string, "[ ] Parent\n  [ ] Child")
            editor.insertBacktab(nil)
            XCTAssertEqual(editor.string, "[ ] Parent\n[ ] Child")
        }
    }

    func testExternalEditMakesRecoverableCopyAndKeepsBothVersions() throws {
        try withController { controller, store in
            controller.editor.insertText("Original", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(controller.save())
            let original = try XCTUnwrap(try store.load().first)
            try "Edited outside".write(to: store.url(for: original), atomically: true, encoding: .utf8)
            controller.editor.insertText(" locally", replacementRange: controller.editor.selectedRange())
            XCTAssertTrue(controller.save())
            XCTAssertEqual(Set(try store.load().map(\.body)), Set(["Edited outside", "Original locally"]))
        }
    }

    func testEscapeKeyDismissesEditorPanel() throws {
        try withController { controller, _ in
            controller.show()
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
            controller.editor.keyDown(with: event)
            XCTAssertFalse(controller.panel.isVisible)
        }
    }

    func testBackspaceAtTaskBodyRemovesTheWholeHiddenMarker() throws {
        try withController { controller, _ in
            let editor = controller.editor
            editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 4, length: 0))
            editor.deleteBackward(nil)
            XCTAssertEqual(editor.string, "Task")
            XCTAssertEqual(editor.selectedRange().location, 0)
        }
    }

    func testWindowFrameClipsTheGlassCornersAndStaysTransparentAfterResize() throws {
        try withController { controller, _ in
            let surface = try XCTUnwrap(controller.panel.contentView)
            let frame = try XCTUnwrap(surface.superview)
            let layer = try XCTUnwrap(frame.layer)
            XCTAssertTrue(layer.masksToBounds)
            XCTAssertEqual(layer.cornerRadius, 26)
            XCTAssertEqual(layer.cornerCurve, .continuous)
            XCTAssertEqual(layer.backgroundColor?.alpha ?? 0, 0)
            controller.panel.setContentSize(NSSize(width: 620, height: 440))
            frame.layoutSubtreeIfNeeded()
            XCTAssertEqual(surface.frame.size, NSSize(width: 620, height: 440))
            XCTAssertTrue(layer.masksToBounds)
            XCTAssertEqual(layer.cornerRadius, 26)
        }
    }

    func testClickingTheVisibleEditorCanReceiveKeyboardInput() throws {
        try withController { controller, _ in
            controller.show()
            let editor = controller.editor
            let root = try XCTUnwrap(controller.panel.contentView)
            let point = editor.convert(NSPoint(x: 12, y: 20), to: root.superview)
            let hit = try XCTUnwrap(root.hitTest(point))
            XCTAssertTrue(hit === editor || hit.isDescendant(of: editor))
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber,
                context: nil, characters: "a", charactersIgnoringModifiers: "a",
                isARepeat: false, keyCode: 0))
            controller.panel.sendEvent(key)
            XCTAssertEqual(editor.string, "a")
        }
    }

    func testSourceToggleRevealsMarkersWithoutChangingMarkdown() throws {
        try withController { controller, _ in
            controller.editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            controller.toggleSource()
            XCTAssertEqual(controller.editor.string, "[ ] Task")
            let font = try XCTUnwrap(controller.editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertGreaterThan(font.pointSize, 10)
        }
    }
}
