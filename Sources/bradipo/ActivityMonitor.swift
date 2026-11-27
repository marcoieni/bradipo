import AppKit
import AVFoundation
import BradipoCore
import CoreGraphics

@MainActor
final class ActivityMonitor {
    var onChange: (() -> Void)?

    private lazy var cameras = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
        mediaType: .video,
        position: .unspecified
    )
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var microphone: MicrophoneMonitor?
    private var systemAsleep = false
    private var screensAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var sessionInactive = false
    private var screenLocked = false
    /// A screen saver that is already running at launch isn't detected.
    private var screenSaverRunning = false

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, in: workspace) { $0.systemAsleep = true }
        observe(NSWorkspace.didWakeNotification, in: workspace) { $0.systemAsleep = false; $0.returned() }
        observe(NSWorkspace.screensDidSleepNotification, in: workspace) { $0.screensAsleep = true }
        observe(NSWorkspace.screensDidWakeNotification, in: workspace) { $0.screensAsleep = false; $0.returned() }
        observe(NSWorkspace.sessionDidResignActiveNotification, in: workspace) { $0.sessionInactive = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, in: workspace) { $0.sessionInactive = false; $0.returned() }
        // The screen can lock or show the screen saver while the display stays on.
        let distributed = DistributedNotificationCenter.default()
        observe(.init("com.apple.screenIsLocked"), in: distributed) { $0.screenLocked = true }
        observe(.init("com.apple.screenIsUnlocked"), in: distributed) { $0.screenLocked = false; $0.screenSaverRunning = false }
        observe(.init("com.apple.screensaver.didstart"), in: distributed) { $0.screenSaverRunning = true }
        observe(.init("com.apple.screensaver.didstop"), in: distributed) { $0.screenSaverRunning = false }

        // Reading after registering means a change in between still arrives as a notification.
        let session = Self.currentSession()
        if let onConsole = session.onConsole { sessionInactive = !onConsole }
        screenLocked = session.screenLocked
    }

    isolated deinit {
        for observer in observers { observer.center.removeObserver(observer.token) }
    }

    func sample(detectMeetings: Bool) -> ActivityState {
        if detectMeetings && microphone == nil {
            microphone = MicrophoneMonitor { [weak self] in self?.onChange?() }
        } else if !detectMeetings {
            microphone = nil
        }
        if systemAsleep || screensAsleep || sessionInactive || screenLocked || screenSaverRunning {
            return .unavailable
        }
        // The camera check is cheap, so let it skip the Core Audio reads behind the microphone check.
        if let microphone, cameras.devices.contains(where: \.isInUseByAnotherApplication) || microphone.isInUse {
            return .meeting
        }
        return .active
    }

    private static func currentSession() -> (onConsole: Bool?, screenLocked: Bool) {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        // The lock key is only present while the screen is locked.
        return (session?[kCGSessionOnConsoleKey as String] as? Bool, session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }

    /// Return events recheck because a missed unlock or `didstop` would otherwise pause reminders indefinitely.
    /// They only clear: a stale "locked" read could silence reminders for hours, while a stale "unlocked" read or
    /// a screen saver that keeps running only lets the countdown run behind it, so a break can pass unseen and the
    /// short/long cycle moves on.
    private func returned() {
        if !Self.currentSession().screenLocked { screenLocked = false }
        screenSaverRunning = false
    }

    /// Clears a dropped unlock or `didstop`. Call it only for input that can't arrive behind the lock screen or a screen saver.
    func notePersonPresent() {
        guard screenLocked || screenSaverRunning else { return }
        screenLocked = false
        screenSaverRunning = false
        onChange?()
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        update: @escaping @MainActor @Sendable (ActivityMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        observers.append((center, token))
    }
}
