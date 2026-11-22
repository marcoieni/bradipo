import AppKit
import BradipoCore
import ColorSync
import Observation
import SwiftUI

@MainActor
final class BreakOverlay: NSObject {
    private var panels: [ReminderPanel] = []
    private var countdown: BreakCountdown?
    private let onEndBreak: () -> Void
    private lazy var sloth = Bundle.main.url(forResource: "Sloth", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    init(onEndBreak: @escaping () -> Void) {
        self.onEndBreak = onEndBreak
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show(secondsRemaining: Int) {
        if let countdown {
            countdown.seconds = secondsRemaining
            return
        }
        countdown = BreakCountdown(seconds: secondsRemaining)
        showOnAllDisplays(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func hide() {
        countdown = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    @objc func resetBanners() {
        BreakCardPlacement.resetAll()
        for panel in panels {
            if let card = panel.contentView as? CardHostingView, let placement = card.placement {
                panel.setFrame(placement.savedFrame, display: true)
                card.scheduleCursorUpdate()
            }
        }
    }

    @objc private func displaysChanged() {
        showOnAllDisplays(animated: false)
    }

    private func showOnAllDisplays(animated: Bool) {
        guard let countdown else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.flatMap { screen in
            // Only the small card receives clicks. The window server delivers input
            // through the full-screen glow directly to the application underneath.
            let glow = ReminderPanel(content: NSHostingView(rootView: ScreenGlow()),
                                     frame: screen.frame, receivesClicks: false)
            let card = CardHostingView(rootView: BreakCard(
                sloth: sloth, countdown: countdown, onEndBreak: onEndBreak
            ))
            let size = card.fittingSize
            let displayID = screen.cgDirectDisplayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? screen.localizedName
            let placement = BreakCardPlacement(displayID: displayID, visibleFrame: screen.visibleFrame, cardSize: size)
            card.placement = placement
            card.sizingOptions = []
            card.rootView.naturalSize = size
            return [glow, ReminderPanel(content: card, frame: placement.savedFrame, receivesClicks: true)]
        }

        for panel in panels {
            panel.alphaValue = animated ? 0 : 1
            panel.orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.55
                panels.forEach { $0.animator().alphaValue = 1 }
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.refreshBannerCursor() }
            }
        } else {
            refreshBannerCursor()
        }
    }

    private func refreshBannerCursor() {
        for panel in panels { (panel.contentView as? CardHostingView)?.scheduleCursorUpdate() }
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderOut(_ sender: Any?) {
        (contentView as? CardHostingView)?.releaseCursor()
        super.orderOut(sender)
    }

    init(content: NSView, frame: NSRect, receivesClicks: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = receivesClicks
        hidesOnDeactivate = false
        ignoresMouseEvents = !receivesClicks
        acceptsMouseMovedEvents = receivesClicks
        if receivesClicks {
            setAccessibilityLabel("Break reminder")
        } else {
            setAccessibilityElement(false)
        }
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
            .stationary, .ignoresCycle,
        ]
        contentView = content
        setFrame(frame, display: true)
    }
}

private final class CardHostingView: NSHostingView<BreakCard> {
    private typealias Corner = BreakCardPlacement.Corner
    private struct Grab {
        let pointer: NSPoint
        let frame: NSRect
        let corner: Corner?
    }

    var placement: BreakCardPlacement?
    private var grab: Grab?
    private var isDragging = false
    private var refreshPending = false
    private static weak var cursorOwner: CardHostingView?
    private lazy var hoverArea = NSTrackingArea(
        rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited, .mouseMoved],
        owner: self, userInfo: nil
    )

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Route gestures on the label and corner grips to the same view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return containsCard(local) || corner(at: local) != nil ? self : nil
    }

    private func containsCard(_ point: NSPoint) -> Bool {
        let radius = min(29, bounds.height / 2)
        return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(point)
    }

    private func gripRect(_ corner: Corner) -> NSRect {
        let side = min(20, bounds.width / 2, bounds.height / 2)
        let atMinY = corner.isBottom != isFlipped
        return NSRect(x: corner.isLeft ? bounds.minX : bounds.maxX - side,
                      y: atMinY ? bounds.minY : bounds.maxY - side, width: side, height: side)
    }

    private func corner(at point: NSPoint) -> Corner? {
        Corner.allCases.first { gripRect($0).contains(point) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // The break panel never becomes key, even when the pointer is over it.
        if !trackingAreas.contains(hoverArea) { addTrackingArea(hoverArea) }
    }

    private func resizeCursor(for corner: Corner) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch corner {
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        case .topLeft: .topLeft
        case .topRight: .topRight
        }
        return .frameResize(position: position, directions: .all)
    }

    // AppKit normally leaves the visible cursor to the foreground app. Resolve
    // this optional WindowServer property at runtime so dragging still works
    // if a future macOS version removes it.
    private static let allowBackgroundCursor: ((Bool) -> Void)? = {
        typealias ConnectionID = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let quartz = CFBundleGetBundleWithIdentifier("com.apple.CoreGraphics" as CFString),
              let idSymbol = CFBundleGetFunctionPointerForName(quartz, "CGSMainConnectionID" as CFString),
              let setSymbol = CFBundleGetFunctionPointerForName(quartz, "CGSSetConnectionProperty" as CFString)
        else { return nil }

        let connection = unsafeBitCast(idSymbol, to: ConnectionID.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetProperty.self)
        return { enabled in
            _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString,
                            enabled ? kCFBooleanTrue : kCFBooleanFalse)
        }
    }()

    func releaseCursor() {
        guard Self.cursorOwner === self else { return }
        Self.allowBackgroundCursor?(false)
        Self.cursorOwner = nil
    }

    func scheduleCursorUpdate() {
        guard !refreshPending else { return }
        refreshPending = true
        // The foreground app can reset the cursor as WindowServer delivers
        // pointer or geometry changes. Reapply it after that event settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            self?.refreshCursor()
        }
    }

    private func refreshCursor() {
        refreshPending = false
        let pointer = NSEvent.mouseLocation
        guard let window, window.isVisible,
              NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0) == window.windowNumber
        else {
            releaseCursor()
            return
        }

        if Self.cursorOwner !== self {
            Self.allowBackgroundCursor?(true)
            Self.cursorOwner = self
        }
        let local = convert(window.convertPoint(fromScreen: pointer), from: nil)
        if let grab, isDragging {
            (grab.corner.map(resizeCursor) ?? .closedHand).set()
        } else if let corner = corner(at: local) {
            resizeCursor(for: corner).set()
        } else {
            (containsCard(local) ? NSCursor.openHand : .arrow).set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        scheduleCursorUpdate()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        scheduleCursorUpdate()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { releaseCursor() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = event.locationInWindow
        grab = Grab(pointer: window.convertPoint(toScreen: point), frame: window.frame,
                    corner: corner(at: convert(point, from: nil)))
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(at: event.locationInWindow)
    }

    private func updateDrag(at point: NSPoint) {
        guard let window, window.isVisible, let grab, let placement else { return }
        let pointer = window.convertPoint(toScreen: point)
        let delta = CGVector(dx: pointer.x - grab.pointer.x, dy: pointer.y - grab.pointer.y)
        guard isDragging || hypot(delta.dx, delta.dy) >= 4 else { return }
        isDragging = true
        if let corner = grab.corner {
            window.setFrame(placement.resize(grab.frame, from: corner, by: delta), display: true)
        } else {
            window.setFrameOrigin(placement.move(to: grab.frame.offsetBy(dx: delta.dx, dy: delta.dy).origin))
        }
        scheduleCursorUpdate()
    }

    override func mouseUp(with event: NSEvent) {
        guard let grab else { return }
        updateDrag(at: event.locationInWindow)
        self.grab = nil
        if !isDragging, grab.corner == nil, window?.isVisible == true, containsCard(convert(event.locationInWindow, from: nil)) {
            rootView.onEndBreak()
        } else {
            scheduleCursorUpdate()
        }
    }
}

@Observable @MainActor
private final class BreakCountdown {
    var seconds: Int
    init(seconds: Int) { self.seconds = seconds }
}

private let sage = Color(red: 0.63, green: 0.78, blue: 0.61)

private struct ScreenGlow: View {
    private func glow(toward end: UnitPoint, from start: UnitPoint) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: sage.opacity(0.43), location: 0),
                .init(color: sage.opacity(0.13), location: 0.38),
                .init(color: .clear, location: 1),
            ],
            startPoint: start, endPoint: end
        )
    }

    var body: some View {
        Rectangle()
            .strokeBorder(sage.opacity(0.73), lineWidth: 2)
            .overlay(alignment: .top) { glow(toward: .bottom, from: .top).frame(height: 44) }
            .overlay(alignment: .bottom) { glow(toward: .top, from: .bottom).frame(height: 44) }
            .overlay(alignment: .leading) { glow(toward: .trailing, from: .leading).frame(width: 44) }
            .overlay(alignment: .trailing) { glow(toward: .leading, from: .trailing).frame(width: 44) }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BreakCard: View {
    let sloth: NSImage?
    let countdown: BreakCountdown
    let onEndBreak: () -> Void
    var naturalSize: CGSize?
    private var hover = State(initialValue: false)

    private let ink = Color(red: 0.12, green: 0.19, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.89)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 29)
        Group {
            if let naturalSize {
                GeometryReader { area in
                    label.scaleEffect(min(area.size.width / naturalSize.width, area.size.height / naturalSize.height))
                        .frame(width: area.size.width, height: area.size.height)
                }
            } else {
                label
            }
        }
        .background(ink, in: shape)
        .overlay { shape.strokeBorder(cream.opacity(0.24), lineWidth: 1) }
        .overlay {
            if hover.wrappedValue {
                Canvas { context, size in
                    var grips = Path()
                    for corner in BreakCardPlacement.Corner.allCases {
                        let x: CGFloat = corner.isLeft ? 4 : size.width - 4
                        let y: CGFloat = corner.isBottom ? size.height - 4 : 4
                        grips.move(to: CGPoint(x: x + (corner.isLeft ? 7 : -7), y: y))
                        grips.addLine(to: CGPoint(x: x, y: y))
                        grips.addLine(to: CGPoint(x: x, y: y + (corner.isBottom ? -7 : 7)))
                    }
                    context.stroke(grips, with: .color(sage), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        // Give the window server a hit target even at the transparent-looking corners.
        .background(Color.black.opacity(0.01))
        .contentShape(Rectangle())
        .onHover { hover.wrappedValue = $0 }
        .focusable(false)
        .help("Drag to move, drag a corner to resize, or click to end this break")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onEndBreak() }
        .accessibilityLabel("End break")
        .accessibilityValue("\(countdown.seconds) seconds remaining")
    }

    private var label: some View {
        HStack(spacing: 12) {
            if let sloth {
                Image(nsImage: sloth)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .frame(width: 42, height: 42)
                    .background(cream, in: Circle())
            }
            Text("Rest your eyes")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(cream)
            Rectangle()
                .fill(sage.opacity(0.40))
                .frame(width: 1, height: 18)
            Text(verbatim: String(format: "%02d:%02d", countdown.seconds / 60, countdown.seconds % 60))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.80, green: 0.87, blue: 0.71))
        }
        .padding(.leading, sloth == nil ? 20 : 8)
        .padding(.trailing, 20)
        .frame(height: 58)
        .fixedSize()
    }
}
