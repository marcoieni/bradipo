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
    private let center = NSWorkspace.shared.notificationCenter
    private var observers: [NSObjectProtocol] = []
    private var microphone: MicrophoneMonitor?
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

    func sample(detectMeetings: Bool) -> ActivityState {
        if detectMeetings && microphone == nil {
            microphone = MicrophoneMonitor { [weak self] in self?.onChange?() }
        } else if !detectMeetings {
            microphone = nil
        }
        if systemAsleep || screensAsleep || sessionInactive { return .unavailable }
        if let microphone, microphone.isInUse || cameras.devices.contains(where: \.isInUseByAnotherApplication) {
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
