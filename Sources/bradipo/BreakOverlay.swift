import AppKit
import Observation
import SwiftUI

@MainActor
final class BreakOverlay: NSObject {
    private var panels: [ReminderPanel] = []
    private var countdown: BreakCountdown?
    private lazy var sloth = Bundle.main.url(forResource: "Sloth", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show(secondsRemaining: Int) {
        guard countdown == nil else {
            update(secondsRemaining: secondsRemaining)
            return
        }
        countdown = BreakCountdown(seconds: secondsRemaining)
        showOnAllDisplays(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func update(secondsRemaining: Int) {
        countdown?.seconds = secondsRemaining
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
        panels = NSScreen.screens.map { screen in
            let panel = ReminderPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isExcludedFromWindowsMenu = true
            panel.animationBehavior = .none
            panel.level = .floating
            panel.collectionBehavior = [
                .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                .stationary, .ignoresCycle,
            ]

            let bottomInset = screen.visibleFrame.minY - screen.frame.minY
            panel.contentView = NSHostingView(rootView: ReminderView(
                sloth: sloth, countdown: countdown, bottomInset: bottomInset
            ))
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = animated ? 0 : 1
            // Order only. Making the panel key would interrupt a field in the active app.
            panel.orderFrontRegardless()
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.55
                    panel.animator().alphaValue = 1
                }
            }
            return panel
        }
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@Observable @MainActor
private final class BreakCountdown {
    var seconds: Int

    init(seconds: Int) {
        self.seconds = seconds
    }
}

private struct ReminderView: View {
    let sloth: NSImage?
    let countdown: BreakCountdown
    let bottomInset: CGFloat

    private let sage = Color(red: 0.63, green: 0.78, blue: 0.61)
    private let ink = Color(red: 0.12, green: 0.19, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.89)

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
        ZStack(alignment: .bottom) {
            Rectangle()
                .strokeBorder(sage.opacity(0.73), lineWidth: 2)
                .overlay(alignment: .top) { glow(toward: .bottom, from: .top).frame(height: 44) }
                .overlay(alignment: .bottom) { glow(toward: .top, from: .bottom).frame(height: 44) }
                .overlay(alignment: .leading) { glow(toward: .trailing, from: .leading).frame(width: 44) }
                .overlay(alignment: .trailing) { glow(toward: .leading, from: .trailing).frame(width: 44) }

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
            .fixedSize()
            .padding(.leading, sloth == nil ? 20 : 8)
            .padding(.trailing, 20)
            .frame(height: 58)
            .background(ink, in: Capsule())
            .overlay { Capsule().strokeBorder(cream.opacity(0.24), lineWidth: 1) }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            .padding(.bottom, bottomInset + 22)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
