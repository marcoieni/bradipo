import AppKit
import BradipoCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pauseStatus = NSMenuItem()
    private let takeBreak = NSMenuItem()
    private let pause = NSMenuItem()
    private let meetingItem = NSMenuItem()
    private let login = LoginItem()
    private let updater = Updater()
    private lazy var glowEditor = BorderGlowEditor(overlay: overlay)
    private lazy var overlay = BreakOverlay { [weak self] in self?.restartTimer() }
    private let activity = ActivityMonitor()
    private var timer: Timer?

    private let defaults = UserDefaults.standard
    @AppStorage(BreakAccent.defaultsKey) private var accent = BreakAccent.green
    private var deferBreaksDuringMeetings: Bool { defaults.bool(forKey: "pauseDuringMeetings") }
    private var clock: BreakTimer
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    override init() {
        defaults.register(defaults: ["workSeconds": 20 * 60, "breakSeconds": 20, "pauseDuringMeetings": true])
        let workSeconds = min(5999, max(1, defaults.integer(forKey: "workSeconds")))
        let breakSeconds = min(5999, max(1, defaults.integer(forKey: "breakSeconds")))
        clock = BreakTimer(workDuration: Double(workSeconds), breakDuration: Double(breakSeconds),
                           now: ProcessInfo.processInfo.systemUptime)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if let button = statusItem.button {
            button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(openMenu(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        activity.onChange = { [weak self] in self?.tick() }
        tick()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        pauseStatus.isEnabled = false
        menu.addItem(pauseStatus)

        takeBreak.target = self
        menu.addItem(takeBreak)
        pause.target = self
        pause.action = #selector(togglePause)
        menu.addItem(pause)
        menu.addItem(withTitle: "Restart Timer", action: #selector(restartTimer), keyEquivalent: "").target = self
        menu.addItem(.separator())
        addDurations(title: "Work interval", seconds: [5, 10, 20, 30, 45, 60].map { $0 * 60 },
                     current: clock.workDuration, action: #selector(changeWork))
        addDurations(title: "Break length", seconds: [20, 30, 60, 120, 300],
                     current: clock.breakDuration, action: #selector(changeBreak))
        menu.addItem(withTitle: "Accent Color…", action: #selector(chooseAccentColor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Border Glow Intensity…", action: #selector(BorderGlowEditor.openEditor),
                     keyEquivalent: "").target = glowEditor
        menu.addItem(withTitle: "Reset Banner Size and Position", action: #selector(BreakOverlay.resetBanners),
                     keyEquivalent: "").target = overlay
        menu.addItem(.separator())
        meetingItem.title = "Defer Breaks During Meetings"
        meetingItem.target = self
        meetingItem.action = #selector(toggleMeetingDeferral)
        menu.addItem(meetingItem)
        menu.addItem(login.menuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "About bradipo", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(updater.menuItem)
        let quit = menu.addItem(withTitle: "Quit bradipo", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "")
        quit.target = NSApp
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        meetingItem.state = deferBreaksDuringMeetings ? .on : .off
        login.refresh()
    }

    @objc private func openMenu(_ button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let frame = button.convert(button.bounds, to: nil)
        let leadingX = NSApp.userInterfaceLayoutDirection == .rightToLeft ? frame.maxX : frame.minX
        var anchor = window.convertPoint(toScreen: NSPoint(x: leadingX, y: 0))
        if let event = NSApp.currentEvent, event.window === window,
           event.type == .leftMouseDown || event.type == .rightMouseDown {
            let pointer = NSEvent.mouseLocation
            // The first click on another display can arrive before AppKit moves the
            // status-item window. Use the click offset and that display's menu bar.
            if !window.frame.contains(pointer),
               let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
                anchor.x = pointer.x + leadingX - event.locationInWindow.x
                anchor.y = min(screen.visibleFrame.maxY, screen.frame.maxY - window.frame.height)
            }
        }
        // popUp positions the menu content. Leave room for its rounded border.
        anchor.y -= 6
        button.highlight(true)
        defer { button.highlight(false) }
        menu.popUp(positioning: nil, at: anchor, in: nil)
    }

    private func addDurations(title: String, seconds: [Int], current: TimeInterval, action: Selector) {
        let submenu = NSMenu(title: title)
        for value in seconds {
            let label = value.isMultiple(of: 60) ? "\(value / 60) min" : "\(value) sec"
            let item = submenu.addItem(withTitle: label, action: action, keyEquivalent: "")
            item.target = self
            item.tag = value
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Custom…", action: action, keyEquivalent: "").target = self
        updateDurationMenu(submenu, seconds: Int(current))
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func updateDurationMenu(_ submenu: NSMenu, seconds: Int) {
        guard let custom = submenu.items.last else { return }
        let selected = submenu.item(withTag: seconds) ?? custom
        custom.title = selected === custom ? String(format: "Custom (%d:%02d)…", seconds / 60, seconds % 60) : "Custom…"
        for item in submenu.items where !item.isSeparatorItem {
            item.state = item === selected ? .on : .off
        }
    }

    private func selectedDuration(_ sender: NSMenuItem, current: TimeInterval) -> Int? {
        guard let submenu = sender.menu else { return nil }
        let isCustom = sender.tag == 0
        let seconds = isCustom ? DurationEditor(title: submenu.title, duration: Int(current)).run() : sender.tag
        if let seconds { updateDurationMenu(submenu, seconds: seconds) }
        return seconds
    }

    @objc private func tick() {
        let state = activity.sample(detectMeetings: deferBreaksDuringMeetings)
        clock.tick(at: now, activity: state)
        render()
    }

    private func render() {
        let time = clock.formattedRemainingTime
        let resting = clock.phase == .resting
        let reason: String? = switch clock.pauseReason {
        case .manual: "Reminders paused"
        case .meeting: "Break due · Mic or camera in use"
        case .idle: "Paused · Mac is idle"
        case .unavailable: "Paused · Mac is away"
        case nil: nil
        }
        if let button = statusItem.button {
            button.title = time
            let description = reason ?? (resting ? "Rest your eyes" : "Work interval")
            button.toolTip = "bradipo · \(description)"
            button.setAccessibilityLabel("bradipo, \(description), \(time)")
        }
        pauseStatus.isHidden = reason == nil || clock.pauseReason == .manual
        pauseStatus.title = reason ?? ""
        takeBreak.title = resting ? "Stop break" : "Take a Break"
        takeBreak.action = resting ? #selector(restartTimer) : #selector(startBreak)
        takeBreak.isEnabled = resting || clock.canStartBreak
        pause.isEnabled = !resting
        pause.title = clock.isManuallyPaused ? "Resume Reminders" : "Pause Reminders"
        if resting {
            overlay.show(timer: clock)
        } else {
            overlay.hide()
        }

        // A headset playing output can stay running when its input stops, so there
        // may be no device notification. Recheck more often while a break is due.
        let delay: TimeInterval = switch clock.pauseReason {
        case .meeting: 0.25
        case nil: clock.timeUntilNextDisplayedSecond
        default: 1
        }
        timer?.invalidate()
        let next = Timer(timeInterval: delay, target: self, selector: #selector(tick), userInfo: nil, repeats: false)
        next.tolerance = 0.02
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    @objc private func startBreak() {
        clock.tick(at: now, activity: activity.sample(detectMeetings: deferBreaksDuringMeetings))
        clock.startBreak(at: now)
        render()
    }

    @objc private func restartTimer() {
        clock.restart(at: now)
        tick()
    }

    @objc private func toggleMeetingDeferral() {
        defaults.set(!deferBreaksDuringMeetings, forKey: "pauseDuringMeetings")
        tick()
    }

    @objc private func chooseAccentColor() {
        // Let the status menu finish returning focus before presenting the panel.
        perform(#selector(showAccentColorPanel), with: nil, afterDelay: 0, inModes: [.default])
    }

    @objc private func showAccentColorPanel() {
        let panel = NSColorPanel.shared
        panel.title = "Accent Color"
        // The menu-bar app can still be inactive after it requests activation.
        panel.hidesOnDeactivate = false
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = accent.color
        panel.setTarget(self)
        panel.setAction(#selector(changeAccentColor(_:)))
        panel.accessoryView = NSButton(title: "Restore Default Green", target: self, action: #selector(resetAccentColor))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        panel.orderFrontRegardless()
    }

    @objc private func changeAccentColor(_ panel: NSColorPanel) {
        if let color = BreakAccent(color: panel.color) { accent = color }
    }

    @objc private func resetAccentColor() {
        accent = .green
        NSColorPanel.shared.color = accent.color
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "github.com/marcoieni/bradipo", attributes: [
                .link: URL(string: "https://github.com/marcoieni/bradipo")!,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]),
        ])
    }

    @objc private func togglePause() {
        clock.setManuallyPaused(!clock.isManuallyPaused, at: now)
        tick()
    }

    @objc private func changeWork(_ sender: NSMenuItem) {
        guard let seconds = selectedDuration(sender, current: clock.workDuration) else { return }
        defaults.set(seconds, forKey: "workSeconds")
        clock.configure(workDuration: Double(seconds), breakDuration: clock.breakDuration, at: now)
        tick()
    }

    @objc private func changeBreak(_ sender: NSMenuItem) {
        guard let seconds = selectedDuration(sender, current: clock.breakDuration) else { return }
        defaults.set(seconds, forKey: "breakSeconds")
        clock.configure(workDuration: clock.workDuration, breakDuration: Double(seconds), at: now)
        tick()
    }
}
