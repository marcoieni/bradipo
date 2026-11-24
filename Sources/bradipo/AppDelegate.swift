import AppKit
import BradipoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pauseStatus = NSMenuItem()
    private let takeBreak = NSMenuItem()
    private let pause = NSMenuItem()
    private let meetingItem = NSMenuItem()
    private let login = LoginItem()
    private lazy var overlay = BreakOverlay { [weak self] in self?.restartTimer() }
    private let activity = ActivityMonitor()
    private var timer: Timer?

    private let defaults = UserDefaults.standard
    private var workSeconds: Int
    private var breakSeconds: Int
    private var deferBreaksDuringMeetings: Bool { defaults.bool(forKey: "pauseDuringMeetings") }
    private var clock: BreakTimer
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    override init() {
        defaults.register(defaults: ["workSeconds": 20 * 60, "breakSeconds": 20, "pauseDuringMeetings": true])
        workSeconds = min(5999, max(1, defaults.integer(forKey: "workSeconds")))
        breakSeconds = min(5999, max(1, defaults.integer(forKey: "breakSeconds")))
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
        let header = NSMenuItem.sectionHeader(title: "bradipo")
        if let url = Bundle.main.url(forResource: "Sloth", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 21, height: 19)
            header.image = image
        }
        menu.addItem(header)
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
                     current: workSeconds, action: #selector(changeWork))
        addDurations(title: "Break length", seconds: [20, 30, 60, 120, 300],
                     current: breakSeconds, action: #selector(changeBreak))
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
