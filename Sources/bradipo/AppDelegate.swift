import AppKit
import BradipoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pauseStatus = NSMenuItem()
    private let takeBreak = NSMenuItem()
    private let pause = NSMenuItem()
    private let overlay = BreakOverlay()
    private let activity = ActivityMonitor()
    private var timer: Timer?

    private let defaults = UserDefaults.standard
    private var workSeconds: Int
    private var breakSeconds: Int
    private var clock: BreakTimer
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    override init() {
        defaults.register(defaults: ["workSeconds": 20 * 60, "breakSeconds": 20])
        workSeconds = min(5999, max(1, defaults.integer(forKey: "workSeconds")))
        breakSeconds = min(5999, max(1, defaults.integer(forKey: "breakSeconds")))
        clock = BreakTimer(workDuration: Double(workSeconds), breakDuration: Double(breakSeconds),
                           now: ProcessInfo.processInfo.systemUptime)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        buildMenu()
        statusItem.menu = menu
        activity.onChange = { [weak self] in self?.tick() }
        tick()
        // Common modes keep the menu-bar clock live while the menu is tracking.
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        let header = NSMenuItem.sectionHeader(title: "bradipo")
        if let url = Bundle.main.url(forResource: "Sloth", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 21, height: 19)
            header.image = image
        }
        menu.addItem(header)
        pauseStatus.isEnabled = false
        menu.addItem(pauseStatus)

        takeBreak.title = "Take a Break"
        takeBreak.target = self
        takeBreak.action = #selector(startBreak)
        menu.addItem(takeBreak)
        pause.target = self
        pause.action = #selector(togglePause)
        menu.addItem(pause)
        menu.addItem(.separator())
        addDurations(title: "Work interval", seconds: [5, 10, 20, 30, 45, 60].map { $0 * 60 },
                     current: workSeconds, action: #selector(changeWork))
        addDurations(title: "Break length", seconds: [20, 30, 60, 120, 300],
                     current: breakSeconds, action: #selector(changeBreak))
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit bradipo", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "")
        quit.target = NSApp
    }

    private func addDurations(title: String, seconds: [Int], current: Int, action: Selector) {
        let submenu = NSMenu(title: title)
        for value in seconds {
            let label = value.isMultiple(of: 60) ? "\(value / 60) min" : "\(value) sec"
            let item = submenu.addItem(withTitle: label, action: action, keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == current ? .on : .off
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func tick() {
        clock.tick(at: now, activity: activity.sample())
        render()
    }

    private func render() {
        let seconds = clock.remainingSeconds
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        let resting = clock.phase == .resting
        let reason: String? = switch clock.pauseReason {
        case .manual: "Reminders paused"
        case .meeting: "Paused · Mic or camera in use"
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
        pauseStatus.isHidden = reason == nil
        pauseStatus.title = reason ?? ""
        takeBreak.isEnabled = !resting && (clock.pauseReason == nil || clock.pauseReason == .idle)
        pause.isEnabled = !resting
        pause.title = clock.isManuallyPaused ? "Resume Reminders" : "Pause Reminders"
        if resting {
            overlay.show(secondsRemaining: seconds)
        } else {
            overlay.hide()
        }
    }

    @objc private func startBreak() {
        clock.tick(at: now, activity: activity.sample())
        clock.startBreak(at: now)
        render()
    }

    @objc private func togglePause() {
        clock.setManuallyPaused(!clock.isManuallyPaused, at: now)
        tick()
    }

    @objc private func changeWork(_ sender: NSMenuItem) {
        workSeconds = sender.tag
        defaults.set(workSeconds, forKey: "workSeconds")
        applyDurations(sender)
    }

    @objc private func changeBreak(_ sender: NSMenuItem) {
        breakSeconds = sender.tag
        defaults.set(breakSeconds, forKey: "breakSeconds")
        applyDurations(sender)
    }

    private func applyDurations(_ selectedItem: NSMenuItem) {
        for item in selectedItem.menu?.items ?? [] {
            item.state = item === selectedItem ? .on : .off
        }
        clock.configure(workDuration: Double(workSeconds), breakDuration: Double(breakSeconds), at: now)
        tick()
    }
}
