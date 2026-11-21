import AppKit
import ServiceManagement

@MainActor
final class LoginItem: NSObject {
    let menuItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
    private let service = SMAppService.mainApp

    override init() {
        super.init()
        menuItem.target = self
        menuItem.action = #selector(toggle)
        refresh()
    }

    func refresh() {
        let status = service.status
        switch status {
        case .enabled: menuItem.state = .on
        case .requiresApproval: menuItem.state = .mixed
        default: menuItem.state = .off
        }
        menuItem.subtitle = status == .requiresApproval ? "Approve in System Settings…" : nil
    }

    @objc private func toggle() {
        defer { refresh() }
        let status = service.status
        do {
            if status == .enabled {
                try service.unregister()
                return
            }
            if status != .requiresApproval {
                try service.register()
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Login Items…")
            NSApp.activate()
            if alert.runModal() == .alertSecondButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
