import AppKit
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
            let cardFrame = NSRect(
                x: (screen.frame.midX - size.width / 2).rounded(),
                y: screen.visibleFrame.minY + 22,
                width: size.width, height: size.height
            )
            return [glow, ReminderPanel(content: card, frame: cardFrame, receivesClicks: true)]
        }

        for panel in panels {
            panel.alphaValue = animated ? 0 : 1
            panel.orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.55
                panels.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(content: NSView, frame: NSRect, receivesClicks: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = receivesClicks
        hidesOnDeactivate = false
        ignoresMouseEvents = !receivesClicks
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
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

    private let ink = Color(red: 0.12, green: 0.19, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.89)

    var body: some View {
        Button(action: onEndBreak) {
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
            .background(ink, in: Capsule())
            .overlay { Capsule().strokeBorder(cream.opacity(0.24), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .focusable(false)
        .help("Click to end this break")
        .accessibilityLabel("End break")
        .accessibilityValue("\(countdown.seconds) seconds remaining")
    }
}
