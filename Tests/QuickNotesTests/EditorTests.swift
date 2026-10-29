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
        let controller = try NotesController(store: store, motion: NoteMotion(reduceMotion: { true }))
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

    func testGlassMaterialAndShadowMaskKeepCornersTransparentAfterResize() throws {
        try withController { controller, _ in
            let effect = try XCTUnwrap(controller.panel.contentView as? NSVisualEffectView)
            for size in [NSSize(width: 400, height: 260), NSSize(width: 620, height: 440)] {
                controller.panel.setContentSize(size)
                effect.layoutSubtreeIfNeeded()
                let mask = try XCTUnwrap(effect.maskImage,
                    "Layer clipping alone leaves the native material and shadow rectangular")
                let rendered = NSImage(size: size, flipped: false) { rect in
                    mask.draw(in: rect)
                    return true
                }
                let pixels = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(rendered.tiffRepresentation)))
                let width = pixels.pixelsWide
                let height = pixels.pixelsHigh
                for (x, y) in [(1, 1), (width - 2, 1), (1, height - 2), (width - 2, height - 2)] {
                    XCTAssertLessThan(try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent, 0.01,
                        "Material and shadow must not fill the rectangular corner at \(size)")
                }
                for (x, y) in [(width / 2, 1), (1, height / 2), (width - 2, height / 2), (width / 2, height - 2)] {
                    XCTAssertGreaterThan(try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent, 0.99,
                        "Resizing must preserve the straight edges of the glass")
                }
                let insetX = Int(30 * CGFloat(width) / size.width)
                let insetY = Int(30 * CGFloat(height) / size.height)
                for (x, y) in [(insetX, insetY), (width - insetX, insetY), (insetX, height - insetY), (width - insetX, height - insetY)] {
                    XCTAssertGreaterThan(try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent, 0.99,
                        "The corner radius must stay fixed instead of stretching with the window")
                }
            }
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

    private func withPinPreference(_ value: Bool?, _ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "keepOnTop")
        defer {
            if let previous { defaults.set(previous, forKey: "keepOnTop") }
            else { defaults.removeObject(forKey: "keepOnTop") }
        }
        if let value { defaults.set(value, forKey: "keepOnTop") }
        else { defaults.removeObject(forKey: "keepOnTop") }
        try body()
    }

    func testNotesStayVisibleAboveOtherWindowsByDefault() throws {
        try withPinPreference(nil) {
            try withController { controller, _ in
                controller.show()
                controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: controller.panel))
                XCTAssertTrue(controller.panel.isVisible)
                XCTAssertGreaterThan(controller.panel.level.rawValue, NSWindow.Level.normal.rawValue)
            }
        }
    }

    func testUnpinRestoresDismissOnBlurAndIsRemembered() throws {
        try withPinPreference(nil) {
            try withController { controller, store in
                controller.togglePin()
                controller.show()
                controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: controller.panel))
                XCTAssertFalse(controller.panel.isVisible)
                let reopened = try NotesController(store: store, motion: NoteMotion(reduceMotion: { true }))
                reopened.show()
                reopened.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: reopened.panel))
                XCTAssertFalse(reopened.panel.isVisible)
                reopened.panel.orderOut(nil)
            }
        }
    }

    func testPinningAgainIsRemembered() throws {
        try withPinPreference(false) {
            try withController { controller, store in
                controller.togglePin()
                let reopened = try NotesController(store: store, motion: NoteMotion(reduceMotion: { true }))
                reopened.show()
                reopened.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: reopened.panel))
                XCTAssertTrue(reopened.panel.isVisible)
                reopened.panel.orderOut(nil)
            }
        }
    }

    func testEmptyCheckboxKeepsAFullHeightCaret() throws {
        try withController { controller, _ in
            let editor = controller.editor
            for character in "[ ] " {
                editor.insertText(String(character), replacementRange: editor.selectedRange())
            }
            editor.layoutManager?.ensureLayout(for: editor.textContainer!)
            let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            XCTAssertGreaterThanOrEqual(caret.height, editor.fontSize)
            XCTAssertEqual(editor.string, "[ ] ")
            editor.insertText("Next", replacementRange: editor.selectedRange())
            XCTAssertEqual(editor.string, "[ ] Next")
        }
    }

    func testReturnAndIndentKeepTheCaretVisibleOnAnEmptyTask() throws {
        try withController { controller, store in
            let editor = controller.editor
            editor.insertText("[ ] Parent", replacementRange: NSRange(location: 0, length: 0))
            editor.insertNewline(nil)
            editor.layoutManager?.ensureLayout(for: editor.textContainer!)
            XCTAssertGreaterThanOrEqual(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil).height, editor.fontSize)
            editor.insertTab(nil)
            editor.layoutManager?.ensureLayout(for: editor.textContainer!)
            XCTAssertGreaterThanOrEqual(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil).height, editor.fontSize)
            XCTAssertTrue(controller.save())
            XCTAssertEqual(try store.load().first?.body, "[ ] Parent\n  [ ] ")
        }
    }

    func testCaretMatchesTheTextLineHeightAtDifferentFontSizes() throws {
        try withController { controller, _ in
            let editor = controller.editor
            for size: CGFloat in [12, 15, 22] {
                editor.fontSize = size
                editor.string = "[ ] Create release\n[ ] "
                editor.restyle()
                let layout = try XCTUnwrap(editor.layoutManager)
                let bodyFont = NSFont.systemFont(ofSize: size, weight: .medium)
                let expectedHeight = layout.defaultLineHeight(for: bodyFont)
                for offset in [4, 10, (editor.string as NSString).length] {
                    editor.setSelectedRange(NSRange(location: offset, length: 0))
                    layout.ensureLayout(for: editor.textContainer!)
                    let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
                    XCTAssertEqual(caret.height, expectedHeight, accuracy: 0.5,
                        "Caret must match the text line at font size \(size), offset \(offset)")
                }
            }
        }
    }

    func testToggleHidesAVisiblePinnedNoteEvenWhenItIsNotKey() throws {
        try withPinPreference(true) {
            try withController { controller, _ in
                controller.show()
                controller.panel.resignKey()
                XCTAssertTrue(controller.panel.isVisible)
                XCTAssertFalse(controller.panel.isKeyWindow)
                controller.toggle()
                XCTAssertFalse(controller.panel.isVisible)
                controller.toggle()
                XCTAssertTrue(controller.panel.isVisible)
                controller.toggle()
                XCTAssertFalse(controller.panel.isVisible)
            }
        }
    }

    func testRevealingPanelTakesKeyboardFocusFromInactiveApplication() throws {
        try withController { controller, _ in
            let previousPolicy = NSApp.activationPolicy()
            defer { NSApp.setActivationPolicy(previousPolicy) }
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            XCTAssertFalse(NSApp.isActive)

            controller.revealPanel()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            XCTAssertTrue(controller.panel.isKeyWindow,
                "Revealing the panel from an inactive app must take keyboard focus without a click")
            XCTAssertTrue(controller.panel.firstResponder === controller.editor)
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
