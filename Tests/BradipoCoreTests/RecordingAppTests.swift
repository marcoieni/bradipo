import BradipoCore
import Testing

@Test func helperAppsBelongToTheOutermostApp() {
    // Electron apps record through a helper app nested inside their frameworks.
    #expect(RecordingApp.appBundlePath(
        containing: "/Applications/T3 Code (Beta).app/Contents/Frameworks/T3 Code (Beta) Helper.app/Contents/MacOS/T3 Code (Beta) Helper"
    ) == "/Applications/T3 Code (Beta).app")
    #expect(RecordingApp.appBundlePath(containing: "/Applications/OBS.app/Contents/MacOS/OBS") == "/Applications/OBS.app")
}

@Test func appBundleExtensionIgnoresCase() {
    // macOS opens Outer.APP as an app, so its helper belongs to it rather than to Inner.app.
    #expect(RecordingApp.appBundlePath(
        containing: "/Applications/Outer.APP/Contents/Frameworks/Inner.app/Contents/MacOS/Inner"
    ) == "/Applications/Outer.APP")
}

@Test func programsOutsideAnAppHaveNoAppBundle() {
    #expect(RecordingApp.appBundlePath(
        containing: "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd"
    ) == nil)
    // Only a directory can be a bundle, so an executable that happens to end in .app doesn't count.
    #expect(RecordingApp.appBundlePath(containing: "/usr/local/bin/recorder.app") == nil)
}

@Test func helperIsIdentifiedByItsApp() {
    let app = RecordingApp(
        executablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper",
        bundleID: "com.hnc.Discord.helper"
    ) { path in
        #expect(path == "/Applications/Discord.app")
        return ("com.hnc.Discord", "Discord")
    }
    // Ignoring Discord has to cover every helper, so the helper's own bundle ID isn't used.
    #expect(app == RecordingApp(id: "com.hnc.Discord", name: "Discord"))
}

@Test func appWithoutABundleIdentifierIsIdentifiedByItsPath() {
    let app = RecordingApp(executablePath: "/Applications/Recorder.app/Contents/MacOS/Recorder", bundleID: "") { _ in
        (nil, "Recorder")
    }
    #expect(app == RecordingApp(id: "/Applications/Recorder.app", name: "Recorder"))
}

@Test func appWithAnEmptyBundleIdentifierIsIdentifiedByItsPath() {
    // Foundation can report "" rather than nil, and two such apps mustn't share one identity.
    let app = RecordingApp(executablePath: "/Applications/Recorder.app/Contents/MacOS/Recorder", bundleID: "") { _ in
        ("", "Recorder")
    }
    #expect(app == RecordingApp(id: "/Applications/Recorder.app", name: "Recorder"))
}

@Test func daemonIsIdentifiedByItsBundleIDAndNamedAfterItsExecutable() {
    let app = RecordingApp(
        executablePath: "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd",
        bundleID: "com.apple.CoreSpeech"
    ) { _ in
        Issue.record("A daemon has no app bundle to look up")
        return (nil, "")
    }
    #expect(app == RecordingApp(id: "com.apple.CoreSpeech", name: "corespeechd"))
}

@Test func programWithoutABundleIDIsIdentifiedByItsPath() {
    // Core Audio reports an empty bundle ID for a command-line program.
    let app = RecordingApp(executablePath: "/opt/homebrew/bin/ffmpeg", bundleID: "") { _ in (nil, "") }
    #expect(app == RecordingApp(id: "/opt/homebrew/bin/ffmpeg", name: "ffmpeg"))
}

@Test func processThatEndedIsIdentifiedByItsBundleIDAlone() {
    // Without a path, the bundle ID is the only name left.
    let app = RecordingApp(executablePath: nil, bundleID: "com.apple.WebKit.GPU") { _ in (nil, "") }
    #expect(app == RecordingApp(id: "com.apple.WebKit.GPU", name: "com.apple.WebKit.GPU"))
    #expect(RecordingApp(executablePath: nil, bundleID: "") { _ in (nil, "") } == nil)
}

@Test func appRecordingThroughSeveralHelpersIsListedOnce() {
    let discord = RecordingApp(id: "com.hnc.Discord", name: "Discord")
    // The names differ, so only a match on the identifier can merge these entries.
    let helper = RecordingApp(id: "com.hnc.Discord", name: "Discord Helper")
    let sections = IgnoredAppsSections(recording: [discord, helper], ignored: [])
    #expect(sections.recording == [discord])
}

@Test func ignoredAppIsListedOnlyAsIgnored() {
    let discord = RecordingApp(id: "com.hnc.Discord", name: "Discord")
    let obs = RecordingApp(id: "com.obsproject.obs-studio", name: "OBS")
    let sections = IgnoredAppsSections(recording: [discord, obs], ignored: [obs])
    #expect(sections.recording == [discord])
    #expect(sections.ignored == [obs])
}

@Test func ignoredAppIsListedWhileItIsNotRecording() {
    let superwhisper = RecordingApp(id: "com.superduper.superwhisper", name: "Superwhisper")
    let sections = IgnoredAppsSections(recording: [], ignored: [superwhisper])
    #expect(sections.recording == [])
    #expect(sections.ignored == [superwhisper])
}

@Test func appsAreSortedByNameIgnoringCase() {
    let corespeechd = RecordingApp(id: "com.apple.CoreSpeech", name: "corespeechd")
    let discord = RecordingApp(id: "com.hnc.Discord", name: "Discord")
    let obs = RecordingApp(id: "com.obsproject.obs-studio", name: "OBS")
    // Core Audio lists processes in the order they first opened audio, which means nothing to the person.
    // A case-sensitive sort would put the lowercase daemon name after both apps.
    let recording = IgnoredAppsSections(recording: [obs, discord, corespeechd], ignored: [])
    #expect(recording.recording == [corespeechd, discord, obs])
    let ignored = IgnoredAppsSections(recording: [], ignored: [obs, corespeechd, discord])
    #expect(ignored.ignored == [corespeechd, discord, obs])
}
