import XCTest
@testable import QuickNotesCore

final class NoteStoreTests: XCTestCase {
    func testPreviewRemovesMarkdownAndTaskMarkersWithoutChangingTheNote() {
        let source = "# Ideas\n**Small notes. Big ideas.**\n[ ] Catch inspiration\n  - [x] Ship **today**"
        let note = Note(body: source)
        XCTAssertEqual(note.preview, "Small notes. Big ideas. · Catch inspiration · Ship today")
        XCTAssertEqual(note.body, source)
    }

    func testPreviewSkipsTheFirstNonemptyTitleAndKeepsReadableLinksAndCode() {
        let source = "\n# Notes\nUse `swift test` and [the docs](https://example.com).\n```swift\napi_client.fetch()\n```"
        XCTAssertEqual(Note(body: source).preview, "Use swift test and the docs. · api_client.fetch()")
        XCTAssertEqual(Note(body: "# Title only").preview, "")
    }

    func testPreviewPreservesLiteralFormattingInsideInlineCode() {
        let note = Note(body: "# Notes\nKeep `**/cache/**` and `a * b * c` literal, with **bold** outside.")
        XCTAssertEqual(note.preview, "Keep **/cache/** and a * b * c literal, with bold outside.")
        XCTAssertEqual(Note(body: "# Notes\n**Use `api_client` today**").preview, "Use api_client today")
    }

    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    func testRoundTripIsPlainMarkdownAndUpdatesOneFile() throws {
        let store = try NoteStore(directory: directory)
        var note = Note(body: "# Release 🚀\n- [ ] Ship\n")
        try store.save(note, expectedBody: nil)
        XCTAssertEqual(try String(contentsOf: store.url(for: note), encoding: .utf8), note.body)
        let previous = note.body
        note.body = "# Release 🚀\n- [x] Ship\n"
        try store.save(note, expectedBody: previous)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.body, note.body)
        XCTAssertEqual(loaded.first?.title, "Release 🚀")
    }
    func testExternalEditsAreNeverOverwritten() throws {
        let store = try NoteStore(directory: directory)
        var note = Note(body: "Original")
        try store.save(note, expectedBody: nil)
        try "External edit".write(to: store.url(for: note), atomically: true, encoding: .utf8)
        note.body = "Local edit"
        XCTAssertThrowsError(try store.save(note, expectedBody: "Original"))
        XCTAssertEqual(try String(contentsOf: store.url(for: note), encoding: .utf8), "External edit")
    }
    func testSearchIncludesBodyAndNewerNotesComeFirst() throws {
        let store = try NoteStore(directory: directory)
        let first = Note(body: "Shopping\nCrème brûlée")
        let second = Note(body: "Work\nRelease checklist")
        try store.save(first, expectedBody: nil)
        try store.save(second, expectedBody: nil)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: store.url(for: first).path)
        let loaded = try store.load()
        XCTAssertEqual(loaded.first?.id, second.id)
        XCTAssertEqual(store.search(loaded, query: "CREME").first?.id, first.id)
        XCTAssertEqual(store.search(loaded, query: "  ").count, 2)
    }
    func testRejectsPathTraversal() throws {
        let store = try NoteStore(directory: directory)
        XCTAssertThrowsError(try store.save(Note(id: "../escape", body: "x"), expectedBody: nil))
    }
    func testUpdatingExternalMarkdownPreservesItsExactFilename() throws {
        let store = try NoteStore(directory: directory)
        let original = directory.appendingPathComponent("UPPER.MD")
        try "Outside".write(to: original, atomically: true, encoding: .utf8)
        var note = try XCTUnwrap(try store.load().first)
        XCTAssertEqual(store.url(for: note).lastPathComponent, "UPPER.MD")
        note.body = "Updated"
        try store.save(note, expectedBody: "Outside")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Updated")
        XCTAssertEqual(try store.load().count, 1)
    }

    func testLoadsExternallyCreatedMarkdownWithoutAnIndex() throws {
        let store = try NoteStore(directory: directory)
        try "[ ] Outside note".write(to: directory.appendingPathComponent("outside.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().first?.title, "Outside note")
    }
}
