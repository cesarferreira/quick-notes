import XCTest
@testable import QuickNotesCore

final class MarkdownTests: XCTestCase {
    func testBareAndNestedTasksHaveUTF16Offsets() {
        let source = "# Launch 🚀\n[ ] Create release\n  - [x] PR 1\n"
        let lines = Markdown.lines(source)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].heading, 1)
        XCTAssertEqual((source as NSString).substring(with: lines[1].bodyRange), "Create release")
        XCTAssertEqual(lines[2].indent, 1)
        XCTAssertTrue(lines[2].checked)
        XCTAssertEqual((source as NSString).substring(with: lines[2].checkRange!), "x")
    }

    func testToggleKeepsOriginalMarkdownAndNestedIndentation() {
        let source = "📝 Today\n  - [ ] Ship **it**\n[ ] Rest"
        XCTAssertEqual(Markdown.togglingTask(source, at: 18), "📝 Today\n  - [x] Ship **it**\n[ ] Rest")
        XCTAssertEqual(Markdown.togglingTask("[X] Done", at: 5), "[ ] Done")
    }

    func testFencedCodeIsNeverInterpretedAsTasks() {
        let lines = Markdown.lines("```md\n[ ] literal\n```\n[ ] Real")
        XCTAssertTrue(lines[1].isCode)
        XCTAssertNil(lines[1].checkRange)
        XCTAssertNotNil(lines[3].checkRange)
    }

    func testReturnContinuesTaskAndExitsEmptyTask() {
        let source = "  - [x] Ship"
        let edit = Markdown.newline(in: source, at: NSRange(location: 12, length: 0))
        XCTAssertEqual(edit.text, "\n  - [ ] ")
        let exit = Markdown.newline(in: "[ ] ", at: NSRange(location: 4, length: 0))
        XCTAssertEqual(exit.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(exit.text, "")
    }

    func testReturnBeforeAListMarkerDoesNotDuplicateIt() {
        XCTAssertEqual(Markdown.newline(in: "- Item", at: NSRange(location: 0, length: 0)).text, "\n")
        XCTAssertEqual(Markdown.newline(in: "[ ] Item", at: NSRange(location: 0, length: 0)).text, "\n")
        XCTAssertEqual(Markdown.newline(in: "# - Heading", at: NSRange(location: 11, length: 0)).text, "\n")
    }

    func testReturnContinuesOrderedListsAndLeavesCodeAlone() {
        XCTAssertEqual(Markdown.newline(in: "9. Next", at: NSRange(location: 7, length: 0)).text, "\n10. ")
        XCTAssertEqual(Markdown.newline(in: "```\n- code", at: NSRange(location: 10, length: 0)).text, "\n")
    }
}
