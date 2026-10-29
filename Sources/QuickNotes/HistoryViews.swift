import AppKit
import QuickNotesCore

final class HistoryNoteCell: NSTableCellView {
    private let titleLabel = label("", size: 13, weight: .semibold, color: .white.withAlphaComponent(0.92))
    private let previewLabel = label("", size: 11, color: .white.withAlphaComponent(0.43))
    private let dateLabel = label("", size: 10, color: .white.withAlphaComponent(0.30))
    private let symbol = NSImageView()
    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("HistoryNoteCell")
        let icon = NSView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 8
        icon.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.contentTintColor = .white.withAlphaComponent(0.45)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.setAccessibilityElement(false)
        icon.addSubview(symbol)
        addSubview(icon)
        addSubview(titleLabel)
        addSubview(previewLabel)
        addSubview(dateLabel)
        textField = titleLabel
        previewLabel.maximumNumberOfLines = 1
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            symbol.centerXAnchor.constraint(equalTo: icon.centerXAnchor), symbol.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 14), symbol.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -12),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            dateLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(note: Note) {
        titleLabel.stringValue = note.title
        let preview = note.preview
        previewLabel.stringValue = preview.isEmpty ? "No additional text" : preview
        dateLabel.stringValue = Self.dateFormatter.localizedString(for: note.modified, relativeTo: Date())
        let checklist = Markdown.lines(note.body).contains { $0.checkRange != nil }
        symbol.image = NSImage(systemSymbolName: checklist ? "checklist" : "note.text", accessibilityDescription: nil)
    }
}

final class HistoryNoteRow: NSTableRowView {
    private var hoverTracking: NSTrackingArea?
    private var hovered = false

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.085).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.07).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard hovered, !isSelected else { return }
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

final class HistoryEmptyView: NSView {
    private let titleLabel = label("", size: 13, weight: .medium, color: .white.withAlphaComponent(0.65))
    private let detailLabel = label("", size: 11, color: .white.withAlphaComponent(0.35))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)!)
        icon.contentTintColor = .white.withAlphaComponent(0.25)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        let stack = NSStackView(views: [icon, titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(hasNotes: Bool) {
        titleLabel.stringValue = hasNotes ? "No matching notes" : "A little space for your thoughts"
        detailLabel.stringValue = hasNotes ? "Try another word or phrase." : "Create your first note with ⌘N."
    }
}
