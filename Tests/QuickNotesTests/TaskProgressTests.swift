import AppKit
import XCTest
import QuickNotesCore
@testable import QuickNotes

final class TaskProgressTests: XCTestCase {
    private func withController(motion: NoteMotion = NoteMotion(reduceMotion: { true }), _ body: (NotesController) throws -> Void) throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = try NotesController(store: NoteStore(directory: folder), motion: motion)
        defer { controller.panel.orderOut(nil) }
        try body(controller)
    }

    private func find(_ id: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.find(id, in: $0) }.first
    }

    private func field(_ id: String, in controller: NotesController) throws -> NSTextField {
        try XCTUnwrap(find(id, in: try XCTUnwrap(controller.panel.contentView)) as? NSTextField)
    }

    func testChecklistCountAndPercentageUpdateOnToggleAndUndo() throws {
        try withController { controller in
            let editor = controller.editor
            editor.insertText("# Launch\n[x] Polish\n  [ ] Smooth\n[ ] Share\n[ ] Celebrate", replacementRange: NSRange(location: 0, length: 0))
            let root = try XCTUnwrap(controller.panel.contentView)
            let footer = try XCTUnwrap(find("TaskProgress", in: root))
            XCTAssertFalse(footer.isHidden)
            XCTAssertEqual(try field("TaskProgressCount", in: controller).stringValue, "1 of 4 completed")
            XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "25%")
            editor.undoManager?.removeAllActions()
            editor.insertTask()
            XCTAssertEqual(try field("TaskProgressCount", in: controller).stringValue, "2 of 4 completed")
            XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "50%")
            editor.undoManager?.undo()
            XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "25%")
        }
    }

    func testFooterAppearsOnlyForRealTasksAndGivesSpaceBackWhenRemoved() throws {
        try withController { controller in
            let root = try XCTUnwrap(controller.panel.contentView)
            let footer = try XCTUnwrap(find("TaskProgress", in: root))
            root.layoutSubtreeIfNeeded()
            let originalHeight = try XCTUnwrap(controller.editor.enclosingScrollView).frame.height
            XCTAssertTrue(footer.isHidden)
            controller.editor.insertText("```md\n[ ] Example\n```", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertTrue(footer.isHidden)
            controller.editor.insertText("\n[ ] Real task", replacementRange: controller.editor.selectedRange())
            root.layoutSubtreeIfNeeded()
            XCTAssertFalse(footer.isHidden)
            XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "0%")
            XCTAssertLessThan(controller.editor.enclosingScrollView!.frame.height, originalHeight)
            controller.editor.insertText("A plain note", replacementRange: NSRange(location: 0, length: (controller.editor.string as NSString).length))
            root.layoutSubtreeIfNeeded()
            XCTAssertTrue(footer.isHidden)
            XCTAssertEqual(controller.editor.enclosingScrollView!.frame.height, originalHeight, accuracy: 0.5)
        }
    }

    func testHistoryAndNewNotesDoNotShowPreviousNotesProgress() throws {
        try withController { controller in
            controller.editor.insertText("[x] Done", replacementRange: NSRange(location: 0, length: 0))
            let footer = try XCTUnwrap(find("TaskProgress", in: controller.panel.contentView!))
            XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "100%")
            controller.toggleHistory()
            XCTAssertTrue(footer.isHidden)
            controller.toggleHistory()
            XCTAssertFalse(footer.isHidden)
            controller.newNote()
            XCTAssertTrue(footer.isHidden)
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertFalse(footer.isHidden)
            XCTAssertEqual(try field("TaskProgressCount", in: controller).stringValue, "1 of 1 completed")
        }
    }

    func testProgressBarUsesExactFractionAndResizesWithThePanel() throws {
        try withController { controller in
            controller.editor.insertText("[X] One\n- [x] Two\n* [ ] Three", replacementRange: NSRange(location: 0, length: 0))
            let root = try XCTUnwrap(controller.panel.contentView)
            let footer = try XCTUnwrap(find("TaskProgress", in: root))
            let track = try XCTUnwrap(footer.subviews.first { $0.accessibilityRole() == .progressIndicator })
            for size in [NSSize(width: 400, height: 260), NSSize(width: 700, height: 450)] {
                controller.panel.setContentSize(size)
                root.layoutSubtreeIfNeeded()
                let fill = try XCTUnwrap(track.layer?.sublayers?.first)
                XCTAssertEqual(fill.frame.width, track.bounds.width * 2 / 3, accuracy: 0.5)
                XCTAssertEqual(try field("TaskProgressPercent", in: controller).stringValue, "67%")
                XCTAssertEqual(track.accessibilityValue() as? Double, 2.0 / 3.0)
                XCTAssertLessThan(footer.frame.height, controller.editor.enclosingScrollView!.frame.height)
            }
        }
    }

    func testSaveErrorHasSpaceAboveTheProgressFooter() throws {
        try withController { controller in
            controller.panel.setContentSize(NSSize(width: 480, height: 310))
            controller.editor.insertText("[ ] Task", replacementRange: NSRange(location: 0, length: 0))
            try FileManager.default.removeItem(at: controller.store.directory)
            try Data().write(to: controller.store.directory)
            XCTAssertFalse(controller.save())
            let root = try XCTUnwrap(controller.panel.contentView)
            root.layoutSubtreeIfNeeded()
            let footer = try XCTUnwrap(find("TaskProgress", in: root))
            let stack = try XCTUnwrap(footer.superview as? NSStackView)
            let message = try XCTUnwrap(stack.views.compactMap { $0 as? NSTextField }.first)
            XCTAssertFalse(message.isHidden)
            XCTAssertGreaterThanOrEqual(message.frame.minY, footer.frame.maxY + 7)
            let editor = try XCTUnwrap(controller.editor.enclosingScrollView)
            XCTAssertGreaterThanOrEqual(editor.frame.minY, stack.frame.maxY + 11)
        }
    }

    func testProgressChangesAnimateOnlyWhenMotionIsEnabled() throws {
        for reduced in [false, true] {
            try withController(motion: NoteMotion(reduceMotion: { reduced })) { controller in
                controller.show()
                let editor = controller.editor
                editor.insertText("[x] One\n[ ] Two", replacementRange: NSRange(location: 0, length: 0))
                let root = try XCTUnwrap(controller.panel.contentView)
                root.layoutSubtreeIfNeeded()
                editor.insertTask()
                let footer = try XCTUnwrap(find("TaskProgress", in: root))
                let track = try XCTUnwrap(footer.subviews.first { $0.accessibilityRole() == .progressIndicator })
                let fill = try XCTUnwrap(track.layer?.sublayers?.first)
                XCTAssertEqual(fill.bounds.width, track.bounds.width, accuracy: 0.5)
                XCTAssertEqual(fill.animationKeys()?.isEmpty ?? true, reduced)
            }
        }
    }
}
