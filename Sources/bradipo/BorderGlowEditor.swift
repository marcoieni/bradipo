import AppKit
import SwiftUI

@MainActor
final class BorderGlowEditor: NSPanel, NSWindowDelegate {
    private let overlay: BreakOverlay

    init(overlay: BreakOverlay) {
        self.overlay = overlay
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow],
                   backing: .buffered, defer: true)
        title = "Border Glow Intensity"
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        delegate = self
        let slider = GlowSlider(intensity: overlay.intensity, setIntensity: overlay.setGlowIntensity) { [weak self] in
            self?.close()
        }
        let content = NSHostingView(rootView: slider)
        contentView = content
        setContentSize(content.fittingSize)
        center()
    }

    func presentPreview() {
        overlay.setGlowPreview(true)
        presentFromMenuBar()
    }

    func windowWillClose(_ notification: Notification) {
        overlay.setGlowPreview(false)
    }
}

private struct GlowSlider: View {
    let intensity: BorderGlowIntensity
    let setIntensity: @MainActor @Sendable (Double) -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Slider(value: Binding(get: { intensity.value }, set: setIntensity)) {
                    Text("Border glow intensity")
                }
                .labelsHidden()
                Text(intensity.value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Previewing on all displays")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 330)
    }
}
