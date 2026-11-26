import AppKit

@MainActor
struct SlothPeek {
    private let button: NSStatusBarButton
    private let sloth: NSImage
    private let title: NSAttributedString
    private let start = ProcessInfo.processInfo.systemUptime

    init?(button: NSStatusBarButton) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let sloth = NSImage(named: "Sloth.png") else { return nil }
        self.button = button
        self.sloth = sloth
        title = button.attributedTitle
    }

    func stop() {
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = title
    }

    /// Returns false once the countdown can take over the button.
    func drawFrame(at now: TimeInterval) -> Bool {
        let progress = (now - start) / 1.5
        guard progress < 1 else { return false }
        func ease(from start: Double, to end: Double) -> Double {
            let t = min(1, max(0, (progress - start) / (end - start)))
            return t * t * (3 - 2 * t)
        }
        let lift = ease(from: 0, to: 0.28) * (1 - ease(from: 0.61, to: 0.86))
        let size = NSSize(width: ceil(title.size().width), height: 22)
        button.image = NSImage(size: size, flipped: false) { [sloth] bounds in
            let width = bounds.height
            let height = width * sloth.size.height / sloth.size.width
            NSGraphicsContext.saveGraphicsState()
            bounds.clip()
            let pose = NSAffineTransform()
            pose.translateX(by: bounds.midX, yBy: (lift - 0.5) * height)
            pose.rotate(byDegrees: 7 * lift)
            pose.concat()
            sloth.draw(in: NSRect(x: -width / 2, y: -height / 2, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        // The title keeps its natural width while the sloth occupies the same space.
        button.imagePosition = .imageOverlaps
        let text = NSMutableAttributedString(attributedString: title)
        let opacity = ease(from: 0.69, to: 0.96)
        text.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(opacity),
                          range: NSRange(location: 0, length: text.length))
        button.attributedTitle = text
        return true
    }
}
