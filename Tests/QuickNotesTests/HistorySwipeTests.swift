import AppKit
import XCTest
import QuickNotesCore
@testable import QuickNotes

final class HistorySwipeTests: XCTestCase {
    private func withHistory(_ body: (NotesController, NoteStore, [Note]) throws -> Void) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastNote")
        defer {
            if let previous { defaults.set(previous, forKey: "lastNote") }
            else { defaults.removeObject(forKey: "lastNote") }
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try NoteStore(directory: directory)
        let notes = [Note(body: "Newest"), Note(body: "Middle"), Note(body: "Oldest")]
        for (index, note) in notes.enumerated() {
            try store.save(note, expectedBody: nil)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(300 - index * 100))], ofItemAtPath: store.url(for: note).path)
        }
        defaults.set(notes[0].id, forKey: "lastNote")
        let controller = try NotesController(store: store, motion: NoteMotion(reduceMotion: { true }))
        try body(controller, store, notes)
        controller.panel.orderOut(nil)
    }

    func testSwipesMoveOneNoteInLastEditedOrderAndStopAtEachEnd() throws {
        try withHistory { controller, store, notes in
            XCTAssertFalse(controller.navigateHistory(.newer))
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[1].id)
            XCTAssertEqual(controller.editor.string, "Middle")
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[2].id)
            XCTAssertFalse(controller.navigateHistory(.older))
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.current.id, notes[1].id)
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.current.id, notes[0].id)
            XCTAssertFalse(controller.navigateHistory(.newer))
            XCTAssertEqual(try store.load().map(\.id), notes.map(\.id), "Viewing a note must not change its edit timestamp")
        }
    }

    func testEditsSaveBeforeSwitchingWithoutReorderingTheSwipeSession() throws {
        try withHistory { controller, store, notes in
            XCTAssertTrue(controller.navigateHistory(.older))
            controller.editor.insertText(" updated", replacementRange: controller.editor.selectedRange())
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[2].id)
            XCTAssertEqual(try store.load().first(where: { $0.id == notes[1].id })?.body, "Middle updated")
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.editor.string, "Middle updated")
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.current.id, notes[0].id)
        }
    }

    func testBlankDraftCanBeLeftAndReturnedToWithoutSavingAnEmptyFile() throws {
        try withHistory { controller, store, notes in
            controller.newNote()
            let draftID = controller.current.id
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[0].id)
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.current.id, draftID)
            XCTAssertEqual(controller.editor.string, "")
            XCTAssertEqual(try store.load().count, 3)
        }
    }

    func testSaveFailureKeepsCurrentDraftInsteadOfNavigating() throws {
        try withHistory { controller, store, notes in
            controller.editor.insertText(" unsaved", replacementRange: controller.editor.selectedRange())
            try FileManager.default.removeItem(at: store.directory)
            try Data().write(to: store.directory)
            XCTAssertFalse(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[0].id)
            XCTAssertEqual(controller.editor.string, "Newest unsaved")
        }
    }

    func testDeletedNotesAreSkippedAndHistoryListIsNotNavigated() throws {
        try withHistory { controller, store, notes in
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertTrue(controller.navigateHistory(.newer))
            try FileManager.default.removeItem(at: store.url(for: notes[1]))
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[2].id)
            controller.toggleHistory()
            XCTAssertFalse(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.current.id, notes[2].id)
        }
    }

    func testNativeTrackpadEventsReachTheNotesHistoryController() throws {
        try withHistory { controller, _, notes in
            _ = try XCTUnwrap(controller.editor.enclosingScrollView as? NotesScrollView)
            func send(_ delta: Int32, _ phase: CGScrollPhase) throws {
                let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                    wheelCount: 2, wheel1: 0, wheel2: delta, wheel3: 0))
                cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
                let event = try XCTUnwrap(NSEvent(cgEvent: cg))
                controller.editor.scrollWheel(with: event)
            }
            try send(20, .began)
            try send(90, .changed)
            try send(0, .ended)
            XCTAssertEqual(controller.current.id, notes[1].id)
            try send(-20, .began)
            try send(-90, .changed)
            try send(0, .ended)
            XCTAssertEqual(controller.current.id, notes[0].id)
        }
    }

    func testNewNoteRefreshesTheOrderAfterEditingAnOlderNote() throws {
        try withHistory { controller, _, notes in
            XCTAssertTrue(controller.navigateHistory(.older))
            controller.editor.insertText(" updated", replacementRange: controller.editor.selectedRange())
            controller.newNote()
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[1].id)
            XCTAssertEqual(controller.editor.string, "Middle updated")
        }
    }

    func testConflictCopyRemainsReachableWhileSwiping() throws {
        try withHistory { controller, store, notes in
            XCTAssertTrue(controller.navigateHistory(.older))
            try "External version".write(to: store.url(for: notes[1]), atomically: true, encoding: .utf8)
            controller.editor.insertText(" local version", replacementRange: controller.editor.selectedRange())
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[2].id)
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.editor.string, "Middle local version")
            XCTAssertEqual(try String(contentsOf: store.url(for: notes[1]), encoding: .utf8), "External version")
            XCTAssertEqual(try store.load().count, 4)
        }
    }

    func testVerticalScrollingWinsAfterASmallHorizontalStart() {
        var gesture = NoteSwipeGesture()
        _ = gesture.update(x: -12, y: 0, phase: .began, momentum: [], inverted: true)
        XCTAssertFalse(gesture.update(x: 0, y: 120, phase: .changed, momentum: [], inverted: true).handled)
        XCTAssertNil(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction)
    }

    func testConflictSavedBeforeASwipeKeepsItsPlaceInHistory() throws {
        try withHistory { controller, store, notes in
            XCTAssertTrue(controller.navigateHistory(.older))
            try "External version".write(to: store.url(for: notes[1]), atomically: true, encoding: .utf8)
            controller.editor.insertText(" local version", replacementRange: controller.editor.selectedRange())
            XCTAssertTrue(controller.save())
            XCTAssertTrue(controller.navigateHistory(.older))
            XCTAssertEqual(controller.current.id, notes[2].id)
            XCTAssertTrue(controller.navigateHistory(.newer))
            XCTAssertEqual(controller.editor.string, "Middle local version")
        }
    }

    func testHorizontalGestureNavigatesOnlyOnceAndIgnoresMomentum() {
        var gesture = NoteSwipeGesture()
        XCTAssertNil(gesture.update(x: -10, y: 0, phase: .began, momentum: [], inverted: true).direction)
        XCTAssertNil(gesture.update(x: -100, y: 1, phase: .changed, momentum: [], inverted: true).direction)
        XCTAssertEqual(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction, .older)
        XCTAssertNil(gesture.update(x: -200, y: 0, phase: [], momentum: .changed, inverted: true).direction)
        XCTAssertNil(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction)
        _ = gesture.update(x: 20, y: 0, phase: .began, momentum: [], inverted: true)
        _ = gesture.update(x: 70, y: 0, phase: .changed, momentum: [], inverted: true)
        XCTAssertEqual(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction, .newer)
    }

    func testVerticalCancelledAndShortGesturesNeverNavigate() {
        var gesture = NoteSwipeGesture()
        XCTAssertFalse(gesture.update(x: 2, y: 30, phase: .began, momentum: [], inverted: true).handled)
        _ = gesture.update(x: -100, y: 40, phase: .changed, momentum: [], inverted: true)
        XCTAssertNil(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction)
        _ = gesture.update(x: -100, y: 0, phase: .began, momentum: [], inverted: true)
        XCTAssertNil(gesture.update(x: 0, y: 0, phase: .cancelled, momentum: [], inverted: true).direction)
        _ = gesture.update(x: -20, y: 0, phase: .began, momentum: [], inverted: true)
        XCTAssertNil(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: true).direction)
        _ = gesture.update(x: 80, y: 0, phase: .began, momentum: [], inverted: false)
        XCTAssertEqual(gesture.update(x: 0, y: 0, phase: .ended, momentum: [], inverted: false).direction, .older)
    }
}
