import BradipoCore
import Testing

@Test func meetingAtDeadlineSuppressesTheBreak() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 19, activity: .active)
    timer.tick(at: 20, activity: .meeting)
    timer.startBreak(at: 20)
    #expect(timer.phase == .working)
    #expect(timer.pauseReason == .meeting)
    #expect(timer.remainingSeconds == 1)

    // Even an hour-long meeting consumes none of the remaining work interval.
    timer.tick(at: 3620, activity: .active)
    #expect(timer.remainingSeconds == 1)
    timer.tick(at: 3621, activity: .active)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 5)
}

@Test func microphoneReleasePreservesTheFractionOfASecondUntilTheNextDigit() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 3.75, activity: .active)
    timer.tick(at: 4, activity: .meeting)

    // The release notification can arrive between any two periodic display updates.
    timer.tick(at: 11.125, activity: .active)
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 17)
    #expect(timer.timeUntilNextDisplayedSecond == 0.25)
    timer.tick(at: 11.375, activity: .active)
    #expect(timer.remainingSeconds == 16)
}

@Test func shortIdlePausesAndLongIdleCountsAsRest() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.tick(at: 55, activity: .active)
    timer.tick(at: 60, activity: .idle(seconds: 60))
    #expect(timer.pauseReason == .idle)
    timer.tick(at: 90, activity: .active)
    #expect(timer.remainingSeconds == 65)

    timer.tick(at: 140, activity: .active)
    timer.tick(at: 200, activity: .idle(seconds: 60))
    timer.tick(at: 440, activity: .idle(seconds: 300))
    timer.tick(at: 441, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 120)
}

@Test func anExplicitBreakRequestWorksWithAssistiveInputWhileIdle() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 80, activity: .idle(seconds: 80))
    #expect(timer.phase == .working)
    timer.startBreak(at: 80)
    #expect(timer.phase == .resting)
    timer.tick(at: 85, activity: .idle(seconds: 85))
    #expect(timer.pauseReason == .idle)
}

@Test func elapsedTimeAndInputDuringARest() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 90, now: 100)
    timer.tick(at: 111.6, activity: .active)
    #expect(timer.remainingSeconds == 109)
    timer.startBreak(at: 112)

    // The existing rest continues when the person looks away, moves the mouse,
    // or the menu's pause action is invoked during a break.
    timer.tick(at: 172, activity: .idle(seconds: 60))
    timer.setManuallyPaused(true, at: 173)
    timer.tick(at: 201, activity: .active)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 1)
    timer.tick(at: 202, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 120)
}

@Test(arguments: [ActivityState.meeting, .unavailable])
func clearsExistingBreakWhenInterrupted(activity: ActivityState) {
    var timer = BreakTimer(workDuration: 20, breakDuration: 10, now: 100)
    timer.startBreak(at: 100)
    timer.tick(at: 104, activity: activity)
    #expect(timer.phase == .working)
    #expect(timer.pauseReason != nil)
    timer.tick(at: 604, activity: .active)
    #expect(timer.remainingSeconds == 20)
}

@Test func resumeRespectsEnvironmentAndSleepResetsWork() {
    var timer = BreakTimer(workDuration: 100, breakDuration: 20, now: 0)
    timer.tick(at: 95, activity: .active)
    timer.setManuallyPaused(true, at: 95)
    timer.tick(at: 110, activity: .meeting)
    timer.setManuallyPaused(false, at: 111)
    #expect(timer.pauseReason == .meeting)
    #expect(timer.remainingSeconds == 5)

    timer.tick(at: 150, activity: .unavailable)
    timer.tick(at: 4600, activity: .active)
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 100)
}

@Test func changesToDurationApplyToTheNextRest() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.startBreak(at: 2)
    timer.configure(workDuration: 60, breakDuration: 5, at: 7)
    timer.tick(at: 12, activity: .active)
    #expect(timer.remainingSeconds == 10)
    timer.tick(at: 22, activity: .active)
    #expect(timer.remainingSeconds == 60)
    timer.tick(at: 82, activity: .active)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 5)
}

@Test func restartingDuringABreakStartsAFreshWorkInterval() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.startBreak(at: 65)
    timer.restart(at: 73)

    // The original break deadline must not end the new work interval.
    timer.tick(at: 85, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 108)
}

@Test func restartClearsManualPauseAndRespectsAnOngoingMeeting() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.tick(at: 60, activity: .active)
    timer.setManuallyPaused(true, at: 60)
    timer.tick(at: 65, activity: .meeting)
    timer.restart(at: 70)
    #expect(timer.pauseReason == .meeting)
    #expect(timer.remainingSeconds == 120)
    timer.tick(at: 90, activity: .active)
    timer.tick(at: 91, activity: .active)
    #expect(timer.remainingSeconds == 119)
}
