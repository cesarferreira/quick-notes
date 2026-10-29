import AppKit
import QuickNotesCore

final class MarkdownTextView: NSTextView {
    var sourceMode = false { didSet { restyle() } }
    var fontSize: CGFloat = 14 { didSet { restyle() } }
    var onDismiss: (() -> Void)?
    var onToggleSource: (() -> Void)?
    private var styledLines: [MarkdownLine] = []
    private var formatting = false

    override var acceptsFirstResponder: Bool { true }

    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 160)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        textContainerInset = NSSize(width: 6, height: 12)
        insertionPointColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        setAccessibilityLabel("Note editor")
        setAccessibilityHelp("Write Markdown. Type open bracket, space, close bracket, space to create a checklist.")
    }

    func restyle() {
        guard !formatting, let storage = textStorage else { return }
        formatting = true
        defer { formatting = false }
        let bodyFont = sourceMode ? NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) : NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = layoutManager?.defaultLineHeight(for: bodyFont) ?? fontSize * 1.2
        // Put spacing between paragraphs so the caret uses the text line height.
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 10
        let base: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(base, range: whole)
        styledLines = Markdown.lines(string)
        if !sourceMode {
            for line in styledLines {
                if line.isCode {
                    storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .backgroundColor: NSColor.labelColor.withAlphaComponent(0.045)], range: line.range)
                    continue
                }
                if line.heading > 0 {
                    let size = fontSize + CGFloat(max(0, 4 - line.heading)) * 3
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: line.bodyRange)
                    let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                    style.paragraphSpacingBefore = 8
                    style.paragraphSpacing = 7
                    storage.addAttribute(.paragraphStyle, value: style, range: line.range)
                }
                if line.checkRange != nil {
                    let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                    style.firstLineHeadIndent = CGFloat(line.indent) * 22 + 25
                    style.headIndent = style.firstLineHeadIndent
                    storage.addAttribute(.paragraphStyle, value: style, range: line.range)
                    if line.checked {
                        storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: line.bodyRange)
                    }
                }
                if let marker = line.markerRange { hide(marker, in: storage) }
                styleInline(line.bodyRange, storage: storage)
            }
        }
        storage.endEditing()
        typingAttributes = base
        needsDisplay = true
    }

    private func hide(_ range: NSRange, in storage: NSTextStorage) {
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear], range: range)
    }

    private func styleInline(_ range: NSRange, storage: NSTextStorage) {
        let patterns: [(String, NSFont?, NSAttributedString.Key?)] = [
            (#"\*\*(.+?)\*\*"#, NSFont.systemFont(ofSize: fontSize, weight: .bold), nil),
            (#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, NSFontManager.shared.convert(NSFont.systemFont(ofSize: fontSize), toHaveTrait: .italicFontMask), nil),
            (#"`([^`\n]+)`"#, NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .medium), .backgroundColor),
            (#"~~(.+?)~~"#, nil, .strikethroughStyle)
        ]
        for (pattern, font, attribute) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: string, range: range) {
                let inner = match.range(at: 1)
                if let font { storage.addAttribute(.font, value: font, range: inner) }
                if attribute == .strikethroughStyle { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner) }
                if attribute == .backgroundColor { storage.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.08), range: inner) }
                hide(NSRange(location: match.range.location, length: inner.location - match.range.location), in: storage)
                hide(NSRange(location: NSMaxRange(inner), length: NSMaxRange(match.range) - NSMaxRange(inner)), in: storage)
            }
        }
        if let links = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\((https?://[^\s)]+)\)"#) {
            for match in links.matches(in: string, range: range) {
                let label = match.range(at: 1)
                let url = (string as NSString).substring(with: match.range(at: 2))
                storage.addAttributes([.link: url, .foregroundColor: NSColor.controlAccentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
                hide(NSRange(location: match.range.location, length: 1), in: storage)
                hide(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), in: storage)
            }
        }
    }

    private func checkboxRect(_ line: MarkdownLine) -> NSRect? {
        guard let layoutManager, let textContainer, line.range.location < (string as NSString).length else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: line.range.location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return NSRect(x: textContainerOrigin.x + CGFloat(line.indent) * 22 + 2,
            y: textContainerOrigin.y + fragment.minY + max(0, (fontSize + 3 - 13) / 2), width: 13, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let placeholder = "Start writing…"
            placeholder.draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y),
                withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor])
        }
        guard !sourceMode else { return }
        for line in styledLines where line.checkRange != nil {
            guard let rect = checkboxRect(line), rect.intersects(dirtyRect) else { continue }
            let box = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
            if line.checked {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
                box.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 6.5))
                check.line(to: NSPoint(x: rect.minX + 5.5, y: rect.minY + 9))
                check.line(to: NSPoint(x: rect.minX + 10, y: rect.minY + 4))
                check.lineWidth = 1.5
                check.lineCapStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                box.fill()
                NSColor.labelColor.withAlphaComponent(0.42).setStroke()
                box.lineWidth = 0.8
                box.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !sourceMode, let line = styledLines.first(where: { $0.checkRange != nil && checkboxRect($0)?.insetBy(dx: -5, dy: -5).contains(point) == true }),
           let check = line.checkRange {
            let selection = selectedRange()
            replace(check, with: line.checked ? " " : "x")
            setSelectedRange(selection)
            return
        }
        super.mouseDown(with: event)
    }

    func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
        didChangeText()
        restyle()
    }

    override func insertNewline(_ sender: Any?) {
        let edit = Markdown.newline(in: string, at: selectedRange())
        replace(edit.range, with: edit.text)
    }


    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if !sourceMode, selection.length == 0,
           let line = styledLines.first(where: { $0.bodyRange.location == selection.location }),
           let marker = line.markerRange {
            replace(marker, with: "")
            return
        }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) { indent(outdent: false) }
    override func insertBacktab(_ sender: Any?) { indent(outdent: true) }
    private func indent(outdent: Bool) {
        let text = string as NSString
        let selection = selectedRange()
        let range = text.lineRange(for: selection)
        let raw = text.substring(with: range)
        let changed = raw.components(separatedBy: "\n").enumerated().map { index, line in
            if line.isEmpty && index > 0 { return line }
            if outdent {
                if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                return line
            }
            return "  " + line
        }.joined(separator: "\n")
        replace(range, with: changed)
        if selection.length == 0 {
            setSelectedRange(NSRange(location: max(range.location, selection.location + (changed as NSString).length - range.length), length: 0))
        } else {
            setSelectedRange(NSRange(location: range.location, length: (changed as NSString).length))
        }
    }

    func wrapSelection(_ marker: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        replace(range, with: marker + selected + marker)
        setSelectedRange(NSRange(location: range.location + (marker as NSString).length, length: range.length))
    }

    func insertTask() {
        let text = string as NSString
        let range = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        if let line = Markdown.lines(string).first(where: { $0.range.location == range.location }), let check = line.checkRange {
            let selection = selectedRange()
            replace(check, with: line.checked ? " " : "x")
            setSelectedRange(selection)
        } else {
            replace(NSRange(location: range.location, length: 0), with: "[ ] ")
        }
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func copy(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((string as NSString).substring(with: selection), forType: .string)
    }
}
