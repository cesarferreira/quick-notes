import AppKit
import QuickNotesCore

final class TaskProgressView: NSView {
    private let motion: NoteMotion
    private let countLabel = label("", size: 11, weight: .medium, color: .white.withAlphaComponent(0.45))
    private let percentLabel = label("", size: 11, weight: .medium, color: .white.withAlphaComponent(0.45))
    private let track = NSView()
    private let fill = CALayer()
    private var trackSize = NSSize.zero
    private(set) var total = 0
    private(set) var completed = 0
    private var fraction: CGFloat { total == 0 ? 0 : CGFloat(completed) / CGFloat(total) }

    init(motion: NoteMotion) {
        self.motion = motion
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("TaskProgress")
        translatesAutoresizingMaskIntoConstraints = false
        countLabel.identifier = NSUserInterfaceItemIdentifier("TaskProgressCount")
        percentLabel.identifier = NSUserInterfaceItemIdentifier("TaskProgressPercent")
        percentLabel.alignment = .right
        track.translatesAutoresizingMaskIntoConstraints = false
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        track.layer?.cornerRadius = 3
        track.layer?.masksToBounds = true
        track.setAccessibilityElement(true)
        track.setAccessibilityRole(.progressIndicator)
        track.setAccessibilityLabel("Checklist completion")
        track.setAccessibilityMinValue(0)
        track.setAccessibilityMaxValue(1)
        fill.backgroundColor = NSColor.white.withAlphaComponent(0.60).cgColor
        fill.cornerRadius = 3
        fill.anchorPoint = .zero
        track.layer?.addSublayer(fill)
        addSubview(countLabel)
        addSubview(percentLabel)
        addSubview(track)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: topAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -12),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            track.heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(source: String, animated: Bool) {
        let previous = fraction
        let tasks = Markdown.lines(source).filter { $0.checkRange != nil }
        total = tasks.count
        completed = tasks.filter(\.checked).count
        countLabel.stringValue = "\(completed) of \(total) completed"
        percentLabel.stringValue = "\(Int((fraction * 100).rounded()))%"
        track.setAccessibilityValue(Double(fraction))
        if fraction != previous { updateFill(animated: animated && motion.isEnabled && window?.isVisible == true) }
    }

    override func layout() {
        super.layout()
        if track.bounds.size != trackSize {
            trackSize = track.bounds.size
            updateFill(animated: false)
        }
    }

    private func updateFill(animated: Bool) {
        let previousWidth = fill.presentation()?.bounds.width ?? fill.bounds.width
        let width = track.bounds.width * fraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = NSRect(x: 0, y: 0, width: width, height: track.bounds.height)
        CATransaction.commit()
        fill.removeAnimation(forKey: "completion")
        guard animated else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = previousWidth
        animation.toValue = width
        animation.duration = 0.20
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fill.add(animation, forKey: "completion")
    }
}
