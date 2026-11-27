import CoreAudio

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

    private let onChange: @MainActor @Sendable () -> Void
    private var system: Listener?
    private let systemProperties = [
        PropertyAddress(kAudioHardwarePropertyServiceRestarted),
        PropertyAddress(kAudioHardwarePropertyDevices),
    ]
    private let running = [PropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)]
    private let inputDevices = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
    private var observed: [AudioObjectID: Listener] = [:]
    private var needsDeviceRefresh = true

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    private func observeSystem() {
        // Each service generation gets its own registrations, even when it reuses device IDs.
        system = Listener(AudioObjectID(kAudioObjectSystemObject), properties: systemProperties) { [weak self] properties in
            guard let self else { return }
            if properties.contains(where: { $0.mSelector == kAudioHardwarePropertyServiceRestarted }) {
                system = nil
                observed.removeAll()
            }
            needsDeviceRefresh = true
            onChange()
        }
    }

    var isInUse: Bool {
        if system == nil { observeSystem() }
        if system != nil, needsDeviceRefresh, let devices = try? AudioHardwareSystem.shared.devices {
            let ids = Set(devices.map(\.id))
            observed = observed.filter { ids.contains($0.key) }
            for id in ids where observed[id] == nil {
                observed[id] = Listener(id, properties: running) { [onChange] _ in onChange() }
            }
            // Retry on the next sample if Core Audio couldn't register a listener.
            needsDeviceRefresh = observed.count != ids.count
        }
        let processes = (try? AudioHardwareSystem.shared.processes) ?? []
        return processes.contains(where: usesRunningMicrophone)
    }

    private func usesRunningMicrophone(_ process: AudioHardwareProcess) -> Bool {
        // CoreSpeech can still report running input after dictation releases the mic.
        // Check the devices used for input so headset playback alone can't delay a break.
        guard (try? process.isRunningInput) == true,
              let data = try? process.propertyData(address: inputDevices) else { return false }
        var ids = [AudioObjectID](repeating: 0, count: data.count / MemoryLayout<AudioObjectID>.stride)
        _ = ids.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return ids.contains { (try? AudioHardwareDevice(id: $0).isRunningInAProcess) == true }
    }
}
