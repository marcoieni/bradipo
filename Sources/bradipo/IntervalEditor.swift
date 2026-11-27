import AppKit

@MainActor
final class IntervalEditor: NSObject, NSTextFieldDelegate {
    enum Setting {
        case duration(Int)
        case shortBreakCount(Int)
    }

    private let alert = NSAlert()
    private let firstField = NSTextField()
    private var seconds: NSTextField?

    init(title: String, setting: Setting) {
        super.init()
        alert.messageText = title
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        func add(_ field: NSTextField, label: String, value: Int, width: CGFloat) {
            field.stringValue = String(value)
            field.delegate = self
            field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
            row.addArrangedSubview(NSTextField(labelWithString: label))
            row.addArrangedSubview(field)
        }
        switch setting {
        case .duration(let duration):
            alert.informativeText = "Enter a duration from 0:01 to 99:59."
            let secondsField = NSTextField()
            seconds = secondsField
            add(firstField, label: "Minutes", value: duration / 60, width: 48)
            add(secondsField, label: "Seconds", value: duration % 60, width: 48)
            firstField.placeholderString = "0"
            secondsField.placeholderString = "0"
            firstField.nextKeyView = secondsField
        case .shortBreakCount(let count):
            alert.informativeText = "How many short breaks should come before each long break?"
            add(firstField, label: "Short breaks", value: count, width: 80)
        }
        row.frame.size = row.fittingSize
        alert.accessoryView = row
        alert.window.initialFirstResponder = firstField
    }

    private var value: Int? {
        guard let seconds else {
            guard let count = Int(firstField.stringValue), count >= 1 else { return nil }
            return count
        }
        func component(_ field: NSTextField) -> Int? {
            let text = field.stringValue
            return text.isEmpty ? 0 : Int(text)
        }
        guard let m = component(firstField), (0...99).contains(m),
              let s = component(seconds), (0...59).contains(s),
              m + s > 0 else { return nil }
        return m * 60 + s
    }

    func controlTextDidChange(_ notification: Notification) {
        alert.buttons[0].isEnabled = value != nil
    }

    func run() -> Int? {
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? value : nil
    }
}
