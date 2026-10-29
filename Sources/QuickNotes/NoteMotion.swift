import AppKit

struct NoteMotion {
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isEnabled: Bool { !reduceMotion() }

    func reveal(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isEnabled ? 0.20 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        guard let layer = panel.contentView?.superview?.layer else { return }
        layer.removeAnimation(forKey: "reveal")
        guard isEnabled else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: centeredScale(0.975, on: layer, offsetY: -5))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = 650
        spring.damping = 32
        spring.duration = 0.24
        layer.add(spring, forKey: "reveal")
    }

    func dismiss(_ panel: NSPanel, completion: @escaping () -> Void) {
        panel.contentView?.superview?.layer?.removeAnimation(forKey: "reveal")
        guard isEnabled else { completion(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    func transition(in view: NSView, direction: NoteHistoryDirection? = nil) {
        view.wantsLayer = true
        view.layer?.removeAnimation(forKey: "noteTransition")
        guard isEnabled, view.window?.isVisible == true else { return }
        let transition = CATransition()
        transition.duration = 0.22
        transition.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        transition.type = direction == nil ? .fade : .push
        if let direction { transition.subtype = direction == .older ? .fromRight : .fromLeft }
        view.layer?.add(transition, forKey: "noteTransition")
    }

    func highlight(_ layer: CALayer, hovered: Bool, pressed: Bool) {
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        let color = NSColor.white.withAlphaComponent(pressed ? 0.14 : (hovered ? 0.075 : 0)).cgColor
        let oldTransform = layer.presentation()?.transform ?? layer.transform
        let transform = centeredScale(pressed && isEnabled ? 0.92 : 1, on: layer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        layer.transform = transform
        CATransaction.commit()
        layer.removeAnimation(forKey: "highlight")
        layer.removeAnimation(forKey: "press")
        guard isEnabled else { return }
        let tint = CABasicAnimation(keyPath: "backgroundColor")
        tint.fromValue = previous
        tint.toValue = color
        tint.duration = 0.14
        layer.add(tint, forKey: "highlight")
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: oldTransform)
        spring.toValue = NSValue(caTransform3D: transform)
        spring.stiffness = 700
        spring.damping = 30
        spring.duration = 0.20
        layer.add(spring, forKey: "press")
    }

    private func centeredScale(_ scale: CGFloat, on layer: CALayer, offsetY: CGFloat = 0) -> CATransform3D {
        let x = layer.bounds.width * (0.5 - layer.anchorPoint.x) * (1 - scale)
        let y = layer.bounds.height * (0.5 - layer.anchorPoint.y) * (1 - scale) + offsetY
        return CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1)
    }
}
