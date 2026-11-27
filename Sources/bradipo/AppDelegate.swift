import AppKit
import BradipoCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var isOpeningOrTrackingMenu = false
    private let pauseStatus = NSMenuItem()
    private let takeBreak = NSMenuItem()
    private let pause = NSMenuItem()
    private let workMenu = NSMenu(title: "Work interval")
    private let breakMenu = NSMenu(title: "Break length")
    private let resetBanners = NSMenuItem(title: "Reset Banner Size and Position", action: #selector(BreakOverlay.resetBanners),
                                          keyEquivalent: "")
    private let meetingItem = NSMenuItem()
    private let login = LoginItem()
    private let updater = Updater()
    private lazy var aboutPanel = AboutPanel()
    private lazy var glowEditor = BorderGlowEditor(overlay: overlay)
    private lazy var overlay = BreakOverlay { [weak self] in self?.endBreak() }
    private let activity = ActivityMonitor()
    private var timer: Timer?
    private var startupPeek: SlothPeek?

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
            button.title = clock.formattedRemainingTime
            if let peek = SlothPeek(button: button) {
                startupPeek = peek
                button.toolTip = "bradipo · Starting work interval"
                button.setAccessibilityLabel("bradipo, starting work interval, \(button.title)")
                let frames = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(animateStartup),
                                   userInfo: nil, repeats: true)
                timer = frames
                RunLoop.main.add(frames, forMode: .common)
                animateStartup()
                return
            }
        }
        startCountdown()
    }

    @objc private func animateStartup() {
        if startupPeek?.drawFrame(at: now) == false { startCountdown() }
    }

    private func startCountdown() {
        timer?.invalidate()
        startupPeek?.stop()
        startupPeek = nil
        let state = activity.sample(detectMeetings: deferBreaksDuringMeetings)
        let start = now
        clock.restart(at: start)
        clock.tick(at: start, activity: state)
        activity.onChange = { [weak self] in self?.tick() }
        render()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag, sender.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) { return true }
        if let button = statusItem.button { openMenu(button) }
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
        addDurations(workMenu, seconds: [5, 10, 20, 30, 45, 60].map { $0 * 60 },
                     action: #selector(changeWork), customAction: #selector(editWorkDuration))
        addDurations(breakMenu, seconds: [20, 30, 60, 120, 300],
                     action: #selector(changeBreak), customAction: #selector(editBreakDuration))
        menu.addItem(withTitle: "Accent Color…", action: #selector(chooseAccentColor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Border Glow Intensity…", action: #selector(editGlowIntensity),
                     keyEquivalent: "").target = self
        resetBanners.target = overlay
        menu.addItem(resetBanners)
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
        resetBanners.isEnabled = overlay.canResetBanners(breakDuration: clock.breakDuration)
        meetingItem.state = deferBreaksDuringMeetings ? .on : .off
        login.refresh()
        updateDurationMenu(workMenu, seconds: Int(clock.workDuration))
        updateDurationMenu(breakMenu, seconds: Int(clock.breakDuration))
    }

    @objc private func openMenu(_ button: NSStatusBarButton) {
        if startupPeek != nil { startCountdown() }
        guard !isOpeningOrTrackingMenu, let window = button.window else { return }
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
        // Return the click or reopen event to macOS before entering menu tracking.
        isOpeningOrTrackingMenu = true
        perform(#selector(trackMenu(at:)), with: NSValue(point: anchor), afterDelay: 0, inModes: [.default])
    }

    @objc private func trackMenu(at position: NSValue) {
        defer { isOpeningOrTrackingMenu = false }
        guard let button = statusItem.button else { return }
        button.highlight(true)
        defer { button.highlight(false) }
        menu.popUp(positioning: nil, at: position.pointValue, in: nil)
    }

    private func addDurations(_ submenu: NSMenu, seconds: [Int], action: Selector, customAction: Selector) {
        for value in seconds {
            let label = value.isMultiple(of: 60) ? "\(value / 60) min" : "\(value) sec"
            let item = submenu.addItem(withTitle: label, action: action, keyEquivalent: "")
            item.target = self
            item.tag = value
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Custom…", action: customAction, keyEquivalent: "").target = self
        menu.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
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
        return isCustom ? DurationEditor(title: submenu.title, duration: Int(current)).run() : sender.tag
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
        takeBreak.action = resting ? #selector(endBreak) : #selector(startBreak)
        takeBreak.isEnabled = resting || clock.canStartBreak
        pause.isEnabled = !resting
        pause.title = clock.isManuallyPaused ? "Resume Reminders" : "Pause Reminders"
        if resting {
            overlay.show(timer: clock)
        } else {
            overlay.hide()
        }

        timer?.invalidate()
        guard let delay = clock.timeUntilNextTick else {
            timer = nil
            return
        }
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

    @objc private func endBreak() {
        clock.endBreak(at: now)
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
        panel.presentFromMenuBar()
    }

    @objc private func changeAccentColor(_ panel: NSColorPanel) {
        if let color = BreakAccent(color: panel.color) { accent = color }
    }

    @objc private func resetAccentColor() {
        accent = .green
        NSColorPanel.shared.color = accent.color
    }

    @objc private func editGlowIntensity() {
        afterMenuCloses(#selector(presentGlowEditor))
    }

    @objc private func presentGlowEditor() {
        glowEditor.presentPreview()
    }

    @objc private func showAbout() {
        afterMenuCloses(#selector(presentAboutPanel))
    }

    private func afterMenuCloses(_ action: Selector, with sender: NSMenuItem? = nil) {
        // The status menu restores focus to the previous app as it closes.
        menu.cancelTrackingWithoutAnimation()
        perform(action, with: sender, afterDelay: 0, inModes: [.default])
    }

    @objc private func presentAboutPanel() {
        aboutPanel.presentFromMenuBar()
    }

    @objc private func togglePause() {
        clock.setManuallyPaused(!clock.isManuallyPaused, at: now)
        tick()
    }

    @objc private func editWorkDuration(_ sender: NSMenuItem) {
        afterMenuCloses(#selector(changeWork), with: sender)
    }

    @objc private func changeWork(_ sender: NSMenuItem) {
        guard let seconds = selectedDuration(sender, current: clock.workDuration) else { return }
        defaults.set(seconds, forKey: "workSeconds")
        clock.configure(workDuration: Double(seconds), breakDuration: clock.breakDuration, at: now)
        tick()
    }

    @objc private func editBreakDuration(_ sender: NSMenuItem) {
        afterMenuCloses(#selector(changeBreak), with: sender)
    }

    @objc private func changeBreak(_ sender: NSMenuItem) {
        guard let seconds = selectedDuration(sender, current: clock.breakDuration) else { return }
        defaults.set(seconds, forKey: "breakSeconds")
        clock.configure(workDuration: clock.workDuration, breakDuration: Double(seconds), at: now)
        tick()
    }
}

extension NSWindow {
    /// Call after the status menu returns focus, on a window that doesn't hide on
    /// deactivation: the menu-bar app can still be inactive after it requests
    /// activation, so the window is ordered front anyway.
    @MainActor func presentFromMenuBar() {
        makeKeyAndOrderFront(nil)
        NSApp.activate()
        orderFrontRegardless()
    }
}
