import BradipoCore
import Testing

@Test func countdownWidthFollowsTheStartingDurationOfEachInterval() {
    var timer = BreakTimer(workDuration: 600, breakDuration: 599, now: 0)
    #expect(timer.formattedRemainingTime == "10:00")
    timer.tick(at: 1, activity: .active)
    #expect(timer.formattedRemainingTime == "09:59")
    timer.startBreak(at: 1)
    #expect(timer.formattedRemainingTime == "9:59")

    // New settings apply to future intervals while the active break keeps its original width.
    timer.configure(workDuration: 300, breakDuration: 600, at: 1)
    timer.tick(at: 595, activity: .active)
    #expect(timer.formattedRemainingTime == "0:05")
    timer.tick(at: 600, activity: .active)
    #expect(timer.formattedRemainingTime == "5:00")
    timer.startBreak(at: 600)
    timer.tick(at: 601, activity: .active)
    #expect(timer.formattedRemainingTime == "09:59")
}

@Test func meetingAtDeadlineDefersOneFullBreakUntilRelease() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 19, activity: .active)
    timer.tick(at: 20, activity: .meeting)
    timer.startBreak(at: 20)
    #expect(timer.phase == .working)
    #expect(timer.pauseReason == .meeting)
    #expect(timer.remainingSeconds == 0)

    timer.tick(at: 3620, activity: .meeting)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 0)

    // macOS can report an hour without keyboard input on the first sample after a call.
    timer.tick(at: 3620.25, activity: .idle(seconds: 3600))
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 5)
    timer.tick(at: 3625.25, activity: .idle(seconds: 3605))
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 20)
}

@Test func dictationCountsTowardTheOriginalWorkDeadline() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 3.75, activity: .active)
    timer.tick(at: 4, activity: .meeting)
    timer.startBreak(at: 4)
    timer.tick(at: 9, activity: .meeting)
    #expect(timer.phase == .working)
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 11)

    timer.tick(at: 11.125, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 9)
    #expect(timer.timeUntilNextDisplayedSecond == 0.875)
    timer.tick(at: 20, activity: .active)
    #expect(timer.phase == .resting)
}

@Test func postMeetingIdleStartsWhenTheDevicesAreReleased() {
    var timer = BreakTimer(workDuration: 600, breakDuration: 5, now: 0)
    timer.tick(at: 1, activity: .meeting)
    timer.tick(at: 400, activity: .idle(seconds: 400))
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 200)

    timer.tick(at: 459, activity: .idle(seconds: 459))
    #expect(timer.remainingSeconds == 141)
    timer.tick(at: 460, activity: .idle(seconds: 460))
    #expect(timer.pauseReason == .idle)
    #expect(timer.remainingSeconds == 141)
    timer.tick(at: 700, activity: .idle(seconds: 700))
    #expect(timer.remainingSeconds == 600)
}

@Test func manualPauseHoldsAnOverdueBreakAndSleepClearsIt() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 5, now: 0)
    timer.tick(at: 25, activity: .meeting)
    timer.setManuallyPaused(true, at: 25)
    timer.tick(at: 30, activity: .active)
    #expect(timer.pauseReason == .manual)
    #expect(timer.remainingSeconds == 0)

    timer.setManuallyPaused(false, at: 35)
    timer.tick(at: 35, activity: .meeting)
    #expect(timer.pauseReason == .meeting)
    timer.tick(at: 36, activity: .unavailable)
    timer.tick(at: 100, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 20)
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

@Test(arguments: [ActivityState.active, .meeting])
func meetingDuringBreakPreservesItsDeadline(activityAtEnd: ActivityState) {
    var timer = BreakTimer(workDuration: 60, breakDuration: 20, now: 0)
    timer.tick(at: 60, activity: .active)
    timer.tick(at: 68, activity: .meeting)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 12)

    // A short dictation can end during the break, while a call can outlast it.
    timer.tick(at: 79, activity: activityAtEnd)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 1)
    timer.tick(at: 80, activity: activityAtEnd)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 60)
    timer.tick(at: 81, activity: activityAtEnd)
    #expect(timer.remainingSeconds == 59)
}

@Test func clearsExistingBreakWhenMacBecomesUnavailable() {
    var timer = BreakTimer(workDuration: 20, breakDuration: 10, now: 100)
    timer.startBreak(at: 100)
    timer.tick(at: 104, activity: .unavailable)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 20)
    timer.tick(at: 108, activity: .active)
    #expect(timer.remainingSeconds == 20)
}

@Test func resumeRespectsEnvironmentAndSleepResetsWork() {
    var timer = BreakTimer(workDuration: 100, breakDuration: 20, now: 0)
    timer.tick(at: 95, activity: .active)
    timer.setManuallyPaused(true, at: 95)
    timer.tick(at: 110, activity: .meeting)
    timer.setManuallyPaused(false, at: 111)
    #expect(!timer.canStartBreak)
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

@Test func restartingDuringABreakRestoresItsFullDuration() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.startBreak(at: 65)
    timer.tick(at: 72, activity: .active)
    // A length change is for the next break. This break still lasts 20 seconds.
    timer.configure(workDuration: 120, breakDuration: 30, at: 72)
    timer.restart(at: 73)
    #expect(timer.phase == .resting)
    #expect(timer.remainingSeconds == 20)

    timer.tick(at: 85, activity: .active)
    #expect(timer.remainingSeconds == 8)
    timer.tick(at: 93, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 120)
}

@Test func stoppingABreakStartsAFreshWorkInterval() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.startBreak(at: 65)
    timer.endBreak(at: 73)

    // The original break deadline must not end the new work interval.
    timer.tick(at: 85, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 108)
}

@Test func restartDuringAMeetingClearsThePendingBreak() {
    var timer = BreakTimer(workDuration: 120, breakDuration: 20, now: 0)
    timer.tick(at: 120, activity: .meeting)
    #expect(timer.pauseReason == .meeting)
    timer.setManuallyPaused(true, at: 121)
    timer.restart(at: 130)
    #expect(timer.pauseReason == nil)
    #expect(timer.remainingSeconds == 120)
    timer.tick(at: 135, activity: .meeting)
    #expect(timer.remainingSeconds == 115)
    timer.tick(at: 140, activity: .active)
    #expect(timer.phase == .working)
    #expect(timer.remainingSeconds == 110)
}
