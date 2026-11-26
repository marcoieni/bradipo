import CoreAudio

@MainActor
final class MicrophoneMonitor {
    private struct Listener: PropertyListenerDelegate {
        let onChange: @MainActor @Sendable () -> Void

        func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
            MainActor.assumeIsolated { onChange() }
        }
    }

    private let listener: Listener
    // Keep this monitor's delegates off the shared AudioHardwareSystem instance.
    private let system = AudioHardwareObject(id: AudioObjectID(kAudioObjectSystemObject))
    private let deviceList = [PropertyAddress(kAudioHardwarePropertyDevices)]
    private let running = [PropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)]
    private let inputDevices = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
    private var observed: [AudioObjectID: AudioHardwareDevice] = [:]
    private var observesDeviceList = false
    private var needsDeviceRefresh = true

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        listener = Listener(onChange: onChange)
        system.delegates = [Listener { [weak self] in
            guard let self else { return }
            needsDeviceRefresh = true
            onChange()
        }]
        observesDeviceList = (try? system.addListener(forProperties: deviceList, dispatchQueue: .main)) != nil
    }

    isolated deinit {
        system.delegates = []
        if observesDeviceList { try? system.removeListener(forProperties: deviceList, dispatchQueue: .main) }
        for device in observed.values { stopObserving(device) }
    }

    private func stopObserving(_ device: AudioHardwareDevice) {
        device.delegates = []
        try? device.removeListener(forProperties: running, dispatchQueue: .main)
    }

    var isInUse: Bool {
        if needsDeviceRefresh, let devices = try? AudioHardwareSystem.shared.devices {
            let ids = Set(devices.map(\.id))
            for (id, device) in observed where !ids.contains(id) {
                stopObserving(device)
                observed.removeValue(forKey: id)
            }
            for device in devices where observed[device.id] == nil {
                device.delegates = [listener]
                if (try? device.addListener(forProperties: running, dispatchQueue: .main)) != nil {
                    observed[device.id] = device
                }
            }
            // Retry on the next sample if Core Audio couldn't register a listener.
            needsDeviceRefresh = !observesDeviceList || observed.count != ids.count
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
