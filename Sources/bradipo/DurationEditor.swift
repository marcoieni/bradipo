import AppKit

@MainActor
final class DurationEditor: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let minutes = NSTextField()
    private let seconds = NSTextField()

    init(title: String, duration: Int) {
        super.init()
        alert.messageText = title
        alert.informativeText = "Enter a duration from 0:01 to 99:59."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        for (field, label, value) in [(minutes, "Minutes", duration / 60), (seconds, "Seconds", duration % 60)] {
            field.stringValue = String(value)
            field.placeholderString = "0"
            field.delegate = self
            field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 48).isActive = true
            row.addArrangedSubview(NSTextField(labelWithString: label))
            row.addArrangedSubview(field)
        }
        row.frame.size = row.fittingSize
        alert.accessoryView = row
        alert.window.initialFirstResponder = minutes
        minutes.nextKeyView = seconds
    }

    private var duration: Int? {
        func component(_ field: NSTextField) -> Int? {
            let text = field.stringValue
            return text.isEmpty ? 0 : Int(text)
        }
        guard let m = component(minutes), (0...99).contains(m),
              let s = component(seconds), (0...59).contains(s),
              m + s > 0 else { return nil }
        return m * 60 + s
    }

    func controlTextDidChange(_ notification: Notification) {
        alert.buttons[0].isEnabled = duration != nil
    }

    func run() -> Int? {
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? duration : nil
    }
}
