import Foundation

public enum ActivityState: Equatable, Sendable {
    case active
    case idle(seconds: TimeInterval)
    case meeting
    case unavailable

    public static let idleThreshold: TimeInterval = 60
    public static let restedThreshold: TimeInterval = 5 * 60

    var countsAsRest: Bool {
        switch self {
        case .unavailable: true
        case .idle(let seconds): seconds >= Self.restedThreshold
        default: false
        }
    }
}

public enum PauseReason: Equatable, Sendable {
    case manual, idle, meeting, unavailable
}

public enum BreakPhase: Equatable, Sendable {
    case working, resting
}

public struct BreakTimer: Sendable {
    public private(set) var phase: BreakPhase = .working
    public private(set) var isManuallyPaused = false
    public var remainingSeconds: Int { Int(ceil(remaining)) }
    public var timeUntilNextDisplayedSecond: TimeInterval { remaining - Double(remainingSeconds - 1) }
    public var pauseReason: PauseReason? {
        guard phase == .working else { return nil }
        if isManuallyPaused { return .manual }
        return switch activity {
        case .active: nil
        case .idle(let seconds): seconds >= ActivityState.idleThreshold ? .idle : nil
        case .meeting: remaining == 0 ? .meeting : nil
        case .unavailable: .unavailable
        }
    }

    public var canStartBreak: Bool {
        phase == .working && !isManuallyPaused && activity != .meeting && activity != .unavailable
    }

    private var workDuration: TimeInterval
    private var breakDuration: TimeInterval
    private var remaining: TimeInterval
    private var lastTick: TimeInterval
    private var activity: ActivityState = .active
    private var lastMeetingEnd: TimeInterval?

    public init(workDuration: TimeInterval, breakDuration: TimeInterval, now: TimeInterval) {
        precondition(workDuration >= 1 && breakDuration >= 1)
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        remaining = workDuration
        lastTick = now
    }

    /// Supply monotonic timestamps and sample the environment before deciding a break is due.
    public mutating func tick(at now: TimeInterval, activity newActivity: ActivityState) {
        let wasPaused = pauseReason != nil
        let elapsed = max(0, now - lastTick)
        lastTick = max(lastTick, now)
        if activity == .meeting && newActivity != .meeting { lastMeetingEnd = lastTick }
        // Keyboard and pointer idle time can span an entire call. Only time away
        // after the call can pause the countdown or count as a rest.
        if case .idle(let seconds) = newActivity, let lastMeetingEnd {
            activity = .idle(seconds: min(seconds, lastTick - lastMeetingEnd))
        } else {
            activity = newActivity
        }

        switch phase {
        case .working:
            if activity.countsAsRest {
                remaining = workDuration
            } else if pauseReason == nil {
                if !wasPaused { remaining = max(0, remaining - elapsed) }
                if remaining == 0 { startBreak(at: now) }
            }
        case .resting:
            // A person looking away during a break should get the whole break.
            // If they join a call or close the laptop, clear the visual immediately.
            remaining -= elapsed
            if remaining <= 0 || activity == .meeting || activity == .unavailable {
                restart(at: now)
            }
        }
    }

    public mutating func restart(at now: TimeInterval) {
        phase = .working
        remaining = workDuration
        isManuallyPaused = false
        lastTick = now
    }

    public mutating func setManuallyPaused(_ paused: Bool, at now: TimeInterval) {
        guard phase == .working, paused != isManuallyPaused else { return }
        isManuallyPaused = paused
        lastTick = now
    }

    public mutating func startBreak(at now: TimeInterval) {
        // Assistive input can activate the menu without resetting macOS's idle clock.
        guard canStartBreak else { return }
        phase = .resting
        remaining = breakDuration
        lastTick = now
    }

    public mutating func configure(
        workDuration: TimeInterval, breakDuration: TimeInterval, at now: TimeInterval
    ) {
        precondition(workDuration >= 1 && breakDuration >= 1)
        if phase == .working && self.workDuration != workDuration {
            remaining = workDuration
            lastTick = now
        }
        self.workDuration = workDuration
        self.breakDuration = breakDuration
    }
}
