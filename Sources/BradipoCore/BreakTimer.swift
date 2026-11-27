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

public enum BreakKind: Sendable {
    case short, long
}

public struct BreakTimer: Sendable {
    public static let defaultLongBreakDuration: TimeInterval = 5 * 60
    public static let defaultShortBreaksBeforeLongBreak = 3

    public var phase: BreakPhase { activeBreak == nil ? .working : .resting }
    /// The current break while resting, or the next scheduled break while working.
    public var breakKind: BreakKind {
        activeBreak?.kind ?? (shortBreaksTaken >= shortBreaksBeforeLongBreak ? .long : .short)
    }
    public private(set) var isManuallyPaused = false
    public private(set) var workDuration: TimeInterval
    /// The short break length, including preferences saved before long breaks were introduced.
    public private(set) var breakDuration: TimeInterval
    public private(set) var longBreakDuration: TimeInterval
    public private(set) var shortBreaksBeforeLongBreak: Int
    public var remainingSeconds: Int { Int(ceil(remaining)) }
    public var formattedRemainingTime: String {
        Self.formatted(seconds: remainingSeconds, duration: activeBreak?.duration ?? workDuration)
    }
    /// Also supplies the natural banner width between breaks.
    public var formattedBreakTime: String {
        if activeBreak != nil { return formattedRemainingTime }
        let duration = nextBreakDuration
        return Self.formatted(seconds: Int(ceil(duration)), duration: duration)
    }

    private static func formatted(seconds: Int, duration: TimeInterval) -> String {
        let format = ceil(duration) < 10 * 60 ? "%d:%02d" : "%02d:%02d"
        return String(format: format, seconds / 60, seconds % 60)
    }
    public var timeUntilNextDisplayedSecond: TimeInterval { remaining - Double(remainingSeconds - 1) }
    public var timeUntilNextTick: TimeInterval? {
        // The workspace reports wake and session changes even without a timer.
        guard activity != .unavailable else { return nil }
        return switch pauseReason {
        // A headset playing output can stay running when its input stops,
        // so a due break needs to recheck even without a device notification.
        case .meeting: 0.25
        case nil: timeUntilNextDisplayedSecond
        default: 1
        }
    }
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

    private var shortBreaksTaken = 0
    private var activeBreak: (kind: BreakKind, duration: TimeInterval)?
    private var nextBreakDuration: TimeInterval { breakKind == .long ? longBreakDuration : breakDuration }
    private var remaining: TimeInterval
    private var lastTick: TimeInterval
    private var activity: ActivityState = .active
    private var lastMeetingEnd: TimeInterval?

    public init(workDuration: TimeInterval, breakDuration: TimeInterval,
                longBreakDuration: TimeInterval = Self.defaultLongBreakDuration,
                shortBreaksBeforeLongBreak: Int = Self.defaultShortBreaksBeforeLongBreak, now: TimeInterval) {
        precondition(workDuration >= 1 && breakDuration >= 1 && longBreakDuration >= 1 && shortBreaksBeforeLongBreak >= 1)
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.longBreakDuration = longBreakDuration
        self.shortBreaksBeforeLongBreak = shortBreaksBeforeLongBreak
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
            remaining -= elapsed
            if remaining <= 0 || activity == .unavailable {
                endBreak(at: now)
            }
        }
    }

    public mutating func restart(at now: TimeInterval) {
        remaining = activeBreak?.duration ?? workDuration
        isManuallyPaused = false
        lastTick = now
    }

    public mutating func endBreak(at now: TimeInterval) {
        guard phase == .resting else { return }
        activeBreak = nil
        restart(at: now)
    }

    public mutating func setManuallyPaused(_ paused: Bool, at now: TimeInterval) {
        guard phase == .working, paused != isManuallyPaused else { return }
        isManuallyPaused = paused
        lastTick = now
    }

    public mutating func startBreak(at now: TimeInterval) {
        // Assistive input can activate the menu without resetting macOS's idle clock.
        guard canStartBreak else { return }
        let kind = breakKind
        let duration = nextBreakDuration
        activeBreak = (kind, duration)
        shortBreaksTaken = kind == .short ? shortBreaksTaken + 1 : 0
        remaining = duration
        lastTick = now
    }

    public mutating func configure(
        workDuration: TimeInterval, breakDuration: TimeInterval,
        longBreakDuration: TimeInterval? = nil, shortBreaksBeforeLongBreak: Int? = nil, at now: TimeInterval
    ) {
        let longDuration = longBreakDuration ?? self.longBreakDuration
        let shortCount = shortBreaksBeforeLongBreak ?? self.shortBreaksBeforeLongBreak
        precondition(workDuration >= 1 && breakDuration >= 1 && longDuration >= 1 && shortCount >= 1)
        if phase == .working && self.workDuration != workDuration {
            remaining = workDuration
            lastTick = now
        }
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.longBreakDuration = longDuration
        self.shortBreaksBeforeLongBreak = shortCount
    }
}
