import BradipoCore
import CoreAudio
import Darwin
import Foundation

@MainActor
final class MicrophoneMonitor {
    @MainActor
    private final class Listener {
        // The imported functions wrap their block argument in a new block on every call,
        // so removal would never match. These C function types pass `block` itself.
        private typealias Block = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void
        private typealias Register = @convention(c) (
            AudioObjectID, UnsafePointer<AudioObjectPropertyAddress>, DispatchQueue?, @escaping Block
        ) -> OSStatus
        private static let add: Register = AudioObjectAddPropertyListenerBlock
        private static let remove: Register = AudioObjectRemovePropertyListenerBlock

        private let id: AudioObjectID
        private let onChange: @MainActor ([AudioObjectPropertyAddress]) -> Void
        private var registered: [AudioObjectPropertyAddress] = []
        private lazy var block: Block = { [weak self] count, addresses in
            let properties = Array(UnsafeBufferPointer(start: addresses, count: Int(count)))
            MainActor.assumeIsolated { self?.onChange(properties) }
        }

        init?(_ id: AudioObjectID, properties: [AudioObjectPropertyAddress],
              onChange: @escaping @MainActor ([AudioObjectPropertyAddress]) -> Void) {
            self.id = id
            self.onChange = onChange
            for var property in properties {
                guard Self.add(id, &property, .main, block) == noErr else { return nil }
                registered.append(property)
            }
        }

        isolated deinit {
            for var property in registered {
                _ = Self.remove(id, &property, .main, block)
            }
        }
    }

    /// A process recording from a running microphone.
    struct Recorder {
        let process: AudioHardwareProcess
        /// Nil if the process has neither a readable path nor a bundle ID, for example because it ended.
        let app: RecordingApp?
    }

    /// Identifiers of apps whose recording doesn't count. A change applies from the next `recorder` read.
    var ignoredApps: Set<String> {
        didSet {
            cachedRecorder = nil
            noRecorderUntil = nil
        }
    }
    private let onChange: @MainActor @Sendable () -> Void
    private var system: Listener?
    private let systemProperties = [
        PropertyAddress(kAudioHardwarePropertyServiceRestarted),
        PropertyAddress(kAudioHardwarePropertyDevices),
    ]
    private let running = [PropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)]
    private let inputStreams = PropertyAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
    private static let inputDevices = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
    private var observed: [AudioObjectID: Listener] = [:]
    private var needsDeviceRefresh = true
    private var cachedRecorder: Recorder?
    /// Until then, reads that don't need to be fresh reuse the last scan, which found no recorder outside `ignoredApps`.
    private var noRecorderUntil: ContinuousClock.Instant?

    init(ignoredApps: Set<String>, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.ignoredApps = ignoredApps
        self.onChange = onChange
    }

    private func observeSystem() {
        // Each service generation gets its own registrations, even when it reuses device IDs.
        system = Listener(AudioObjectID(kAudioObjectSystemObject), properties: systemProperties) { [weak self] properties in
            guard let self else { return }
            noRecorderUntil = nil
            if properties.contains(where: { $0.mSelector == kAudioHardwarePropertyServiceRestarted }) {
                system = nil
                observed.removeAll()
                // A new service generation can reuse the recorder's object ID for another process.
                cachedRecorder = nil
            }
            needsDeviceRefresh = true
            onChange()
        }
    }

    /// Pass `fresh` when the result decides whether a break starts, or is about to show in the menu.
    func recorder(fresh: Bool) -> Recorder? {
        if system == nil { observeSystem() }
        lazy var devices = try? AudioHardwareSystem.shared.devices
        if system != nil, needsDeviceRefresh, let devices {
            let ids = Set(devices.map(\.id))
            observed = observed.filter { ids.contains($0.key) }
            for id in ids where observed[id] == nil {
                observed[id] = Listener(id, properties: running) { [weak self] _ in
                    guard let self else { return }
                    noRecorderUntil = nil
                    onChange()
                }
            }
            // Retry on the next sample if Core Audio couldn't register a listener.
            needsDeviceRefresh = observed.count != ids.count
        }
        // During a call the same process keeps recording, so check it first.
        if let cachedRecorder, Self.usesRunningMicrophone(cachedRecorder.process) { return cachedRecorder }
        cachedRecorder = nil
        // An ignored app can keep the microphone running all day, and scanning every audio client costs about 5 ms.
        // Reads that could start a break or open the menu are fresh. The others only keep the break actions of an
        // open menu current, so they can reuse a scan that found no recorder for up to 10 s. Device changes end that sooner.
        if !fresh, let noRecorderUntil, ContinuousClock.now < noRecorderUntil { return nil }
        // Reading every audio client is costly, so skip it unless a device with input streams is running.
        // This assumes recorders use a listed device: Core Audio's device list leaves out hidden devices.
        if let devices, !devices.contains(where: isRunningMicrophone) { return nil }
        guard let processes = try? AudioHardwareSystem.shared.processes else { return nil }
        for process in processes where Self.usesRunningMicrophone(process) {
            let app = RecordingApp(process)
            if let app, ignoredApps.contains(app.id) { continue }
            cachedRecorder = Recorder(process: process, app: app)
            break
        }
        noRecorderUntil = cachedRecorder == nil ? .now + .seconds(10) : nil
        return cachedRecorder
    }

    /// Every app recording from a running microphone, ignored or not, with an entry for each recording process.
    static func recordingApps() -> [RecordingApp] {
        let processes = (try? AudioHardwareSystem.shared.processes) ?? []
        return processes.filter(usesRunningMicrophone).compactMap(RecordingApp.init)
    }

    private func isRunningMicrophone(_ device: AudioHardwareDevice) -> Bool {
        // A device's stream configuration can change without a device-list change, so read it each time.
        // Rule a device out only when it's known to be idle or to have no input streams,
        // so an error costs a scan rather than a missed meeting.
        // Check the streams first: asking the speakers whether they're running can block for about 150 ms
        // while a voice-processing call starts or stops.
        (try? device.propertyDataSize(address: inputStreams)) != 0
            && (try? device.isRunningInAProcess) != false
    }

    private static func usesRunningMicrophone(_ process: AudioHardwareProcess) -> Bool {
        // CoreSpeech can still report running input after dictation releases the mic.
        // Check the devices used for input so headset playback alone can't delay a break.
        guard (try? process.isRunningInput) == true,
              let data = try? process.propertyData(address: inputDevices) else { return false }
        var ids = [AudioObjectID](repeating: 0, count: data.count / MemoryLayout<AudioObjectID>.stride)
        _ = ids.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return ids.contains { (try? AudioHardwareDevice(id: $0).isRunningInAProcess) == true }
    }
}

extension RecordingApp {
    /// Names the app behind an audio process. Core Audio often lists a helper, such as Discord Helper for Discord.
    init?(_ process: AudioHardwareProcess) {
        self.init(executablePath: (try? process.pid).flatMap(Self.executablePath), bundleID: try? process.bundleID) { path in
            let name = FileManager.default.displayName(atPath: path)
            // Finder can be set to show every file extension.
            return (Bundle(path: path)?.bundleIdentifier, name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name)
        }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        // `NSRunningApplication` only knows apps, not the helpers and daemons that often do the recording.
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        if length > 0 { return String(decoding: path.prefix(Int(length)), as: UTF8.self) }
        // That fails once an update replaces the executable of an app that's still running.
        // The path the process started from follows the argument count in its arguments, but can be relative.
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
        var arguments = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &arguments, &size, nil, 0) == 0, size > 4 else { return nil }
        let started = String(decoding: arguments[4..<size].prefix { $0 != 0 }, as: UTF8.self)
        return started.hasPrefix("/") ? started : nil
    }
}
