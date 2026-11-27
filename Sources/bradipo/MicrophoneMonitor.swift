import CoreAudio

@MainActor
final class MicrophoneMonitor {
    private struct Listener: PropertyListenerDelegate {
        let onChange: @MainActor @Sendable ([AudioObjectPropertyAddress]) -> Void

        func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
            MainActor.assumeIsolated { onChange(properties) }
        }
    }

    private let onChange: @MainActor @Sendable () -> Void
    private var system: AudioHardwareObject?
    private let systemProperties = [
        PropertyAddress(kAudioHardwarePropertyServiceRestarted),
        PropertyAddress(kAudioHardwarePropertyDevices),
    ]
    private let running = [PropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)]
    private let inputDevices = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
    private var observed: [AudioObjectID: AudioHardwareDevice] = [:]
    private var needsDeviceRefresh = true

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    private func observeSystem() {
        // Each service generation gets its own registrations, even when it reuses device IDs.
        let system = AudioHardwareObject(id: AudioObjectID(kAudioObjectSystemObject))
        system.delegates = [Listener { [weak self] properties in
            guard let self else { return }
            if properties.contains(where: { $0.mSelector == kAudioHardwarePropertyServiceRestarted }) {
                removeListeners()
            }
            needsDeviceRefresh = true
            onChange()
        }]
        do {
            try system.addListener(forProperties: systemProperties, dispatchQueue: .main)
            self.system = system
        } catch {
            stopObserving(system, properties: systemProperties)
        }
    }

    isolated deinit {
        removeListeners()
    }

    private func removeListeners() {
        if let system { stopObserving(system, properties: systemProperties) }
        system = nil
        for device in observed.values { stopObserving(device, properties: running) }
        observed.removeAll()
    }

    private func stopObserving(_ object: AudioHardwareObject, properties: [AudioObjectPropertyAddress]) {
        object.delegates = []
        // A failed registration or a service reset may leave only some properties registered.
        for property in properties {
            try? object.removeListener(forProperties: [property], dispatchQueue: .main)
        }
    }

    var isInUse: Bool {
        if system == nil { observeSystem() }
        if needsDeviceRefresh, let devices = try? AudioHardwareSystem.shared.devices {
            let ids = Set(devices.map(\.id))
            for (id, device) in observed where !ids.contains(id) {
                stopObserving(device, properties: running)
                observed.removeValue(forKey: id)
            }
            for device in devices where observed[device.id] == nil {
                device.delegates = [Listener { [onChange] _ in onChange() }]
                if (try? device.addListener(forProperties: running, dispatchQueue: .main)) != nil {
                    observed[device.id] = device
                }
            }
            // Retry on the next sample if Core Audio couldn't register a listener.
            needsDeviceRefresh = system == nil || observed.count != ids.count
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
