import AppKit
import XCTest
import QuickNotesCore
@testable import QuickNotes

final class HistoryTests: XCTestCase {
    private func withHistory(_ body: (NotesController, Note) throws -> Void) throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try NoteStore(directory: folder)
        try store.save(Note(body: "# Release\n[ ] Ship it"), expectedBody: nil)
        let idea = Note(body: "# Ideas\n**A spark** of inspiration\n[ ] Make it happen")
        try store.save(idea, expectedBody: nil)
        let controller = try NotesController(store: store, motion: NoteMotion(reduceMotion: { true }))
        defer { controller.panel.orderOut(nil) }
        try body(controller, idea)
    }

    func testHistoryShowsReadablePreviewsAndOpensTheUnchangedMarkdown() throws {
        try withHistory { controller, idea in
            controller.show()
            controller.toggleHistory()
            controller.search.stringValue = "spark"
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.search))
            XCTAssertEqual(controller.numberOfRows(in: controller.table), 1)
            let cell = try XCTUnwrap(controller.tableView(controller.table, viewFor: nil, row: 0))
            func text(in view: NSView) -> [String] {
                (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { text(in: $0) }
            }
            XCTAssertTrue(text(in: cell).contains("A spark of inspiration · Make it happen"))
            let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: controller.panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            controller.table.keyDown(with: key)
            XCTAssertEqual(controller.current.id, idea.id)
            XCTAssertEqual(controller.editor.string, idea.body)
            XCTAssertTrue(controller.panel.firstResponder === controller.editor)
        }
    }

    func testEmptySearchDoesNotOpenAStaleSelection() throws {
        try withHistory { controller, _ in
            let originalID = controller.current.id
            controller.toggleHistory()
            controller.search.stringValue = "nothing-matches-this-query"
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.search))
            XCTAssertEqual(controller.numberOfRows(in: controller.table), 0)
            controller.openSelectedNote()
            XCTAssertEqual(controller.current.id, originalID)
        }
    }
}
