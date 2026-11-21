import AppKit
import AVFoundation
import BradipoCore
import CoreAudio
import CoreGraphics

@MainActor
final class ActivityMonitor {
    var onChange: (() -> Void)?

    private let cameras = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
        mediaType: .video,
        position: .unspecified
    )
    private let center = NSWorkspace.shared.notificationCenter
    private var observers: [NSObjectProtocol] = []
    private var systemAsleep = false
    private var screensAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var sessionInactive = false

    init() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool {
            sessionInactive = !onConsole
        }
        observe(NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
    }

    isolated deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    func sample() -> ActivityState {
        if systemAsleep || screensAsleep || sessionInactive { return .unavailable }
        if cameras.devices.contains(where: \.isInUseByAnotherApplication) { return .meeting }

        // Check input streams specifically. Music played through a headset with a
        // built-in microphone should never pause the timer.
        if let processes = try? AudioHardwareSystem.shared.processes,
           processes.contains(where: { (try? $0.isRunningInput) == true }) {
            return .meeting
        }

        // Swift does not import the C macro kCGAnyInputEventType.
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return idle >= ActivityState.idleThreshold ? .idle(seconds: idle) : .active
    }

    private func observe(
        _ name: Notification.Name,
        update: @escaping @MainActor @Sendable (ActivityMonitor) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        observers.append(observer)
    }
}
