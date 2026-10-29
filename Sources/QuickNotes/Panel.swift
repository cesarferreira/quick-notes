import AppKit

func roundedMaterialMask(radius: CGFloat) -> NSImage {
    // Continuous corners extend beyond the radius; keep that entire curve in
    // each fixed cap and stretch only the one-point strip between the caps.
    let cap = radius * 2
    let size = NSSize(width: cap * 2 + 1, height: cap * 2 + 1)
    let image = NSImage(size: size, flipped: false) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        let shape = CALayer()
        shape.frame = rect
        shape.backgroundColor = NSColor.black.cgColor
        shape.cornerRadius = radius
        shape.cornerCurve = .continuous
        shape.render(in: context)
        return true
    }
    image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
    image.resizingMode = .stretch
    return image
}

final class NoteSurface: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.02, alpha: 0.42).setFill()
        dirtyRect.fill()
    }
}

final class NotesPanel: NSPanel {
    var shortcut: ((String, NSEvent.ModifierFlags) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shortcut?(event.charactersIgnoringModifiers?.lowercased() ?? "", event.modifierFlags.intersection(.deviceIndependentFlagsMask)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class DragArea: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class IconButton: NSButton {
    init(symbol: String, label: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .accessoryBarAction
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class HistoryTable: NSTableView {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { onOpen?(); return }
        if event.keyCode == 53 { onDismiss?(); return }
        super.keyDown(with: event)
    }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}
