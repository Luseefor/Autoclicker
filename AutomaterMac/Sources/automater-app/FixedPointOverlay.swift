import AppKit
import QuartzCore

/// Glowing laser marker for the fixed point: pulsing neon crosshair + rings,
/// drawn in a transparent panel that floats above everything on every Space
/// and never intercepts clicks.
final class FixedPointOverlayController {
    private var panel: NSPanel?
    private static let side: CGFloat = 160

    func setVisible(_ visible: Bool, at cgPoint: CGPoint) {
        if visible {
            let panel = ensurePanel()
            panel.setFrame(Self.panelRect(around: cgPoint), display: true)
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true          // clicks pass through to the target
        panel.level = .statusBar                 // above every normal window
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let glow = GlowView(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        panel.contentView = glow
        self.panel = panel
        return panel
    }

    /// CG point (top-left origin) → panel rect centered on it.
    static func panelRect(around cgPoint: CGPoint) -> NSRect {
        let primaryHeight = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        let cocoa = CGPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
        return NSRect(x: cocoa.x - side / 2, y: cocoa.y - side / 2,
                      width: side, height: side)
    }
}

/// Neon target: white-hot core, red glowing ring + crosshair, pulsing.
private final class GlowView: NSView {

    override func viewDidMoveToWindow() {
        wantsLayer = true
        guard window != nil, layer?.sublayers == nil || layer?.sublayers?.isEmpty == true else { return }
        buildLayers()
    }

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func buildLayers() {
        let c = center
        let neon = NSColor.systemRed.cgColor

        // faint outer ring
        addRing(radius: 34, width: 1.2, color: neon, glow: 6, opacity: 0.45, pulse: false)

        // main pulsing ring
        addRing(radius: 22, width: 2.6, color: neon, glow: 12, opacity: 1.0, pulse: true)

        // crosshair with a gap around the core
        let cross = CAShapeLayer()
        cross.path = crosshairPath(center: c, gap: 28, length: 74)
        cross.strokeColor = neon
        cross.fillColor = NSColor.clear.cgColor
        cross.lineWidth = 1.6
        cross.lineCap = .round
        cross.shadowColor = neon
        cross.shadowOpacity = 0.9
        cross.shadowRadius = 7
        cross.shadowOffset = .zero
        cross.opacity = 0.9
        addPulse(to: cross, from: 0.55, to: 1.0, duration: 0.9)
        layer?.addSublayer(cross)

        // white-hot core dot
        let dot = CALayer()
        dot.frame = CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)
        dot.cornerRadius = 2.5
        dot.backgroundColor = NSColor.white.cgColor
        dot.shadowColor = neon
        dot.shadowOpacity = 1.0
        dot.shadowRadius = 9
        dot.shadowOffset = .zero
        layer?.addSublayer(dot)
    }

    private func addRing(radius: CGFloat, width: CGFloat, color: CGColor,
                         glow: CGFloat, opacity: CGFloat, pulse: Bool) {
        let ring = CAShapeLayer()
        ring.path = CGPath(
            ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2),
            transform: nil)
        ring.strokeColor = color
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = width
        ring.shadowColor = color
        ring.shadowOpacity = 0.95
        ring.shadowRadius = glow
        ring.shadowOffset = .zero
        ring.opacity = Float(opacity)
        if pulse { addPulse(to: ring, from: Float(opacity * 0.5), to: Float(opacity), duration: 0.75) }
        layer?.addSublayer(ring)
    }

    private func addPulse(to layer: CALayer, from: Float, to: Float, duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "neonPulse")
    }

    private func crosshairPath(center c: CGPoint, gap: CGFloat, length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - length, y: c.y)); path.addLine(to: CGPoint(x: c.x - gap, y: c.y))
        path.move(to: CGPoint(x: c.x + gap, y: c.y)); path.addLine(to: CGPoint(x: c.x + length, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - length)); path.addLine(to: CGPoint(x: c.x, y: c.y - gap))
        path.move(to: CGPoint(x: c.x, y: c.y + gap)); path.addLine(to: CGPoint(x: c.x, y: c.y + length))
        return path
    }
}
