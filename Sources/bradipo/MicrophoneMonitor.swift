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
    private let running = [PropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)]
    private let inputDevices = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
    private var observed: [AudioObjectID: AudioHardwareDevice] = [:]

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        listener = Listener(onChange: onChange)
    }

    isolated deinit {
        for device in observed.values { stopObserving(device) }
    }

    private func stopObserving(_ device: AudioHardwareDevice) {
        device.delegates = []
        try? device.removeListener(forProperties: running, dispatchQueue: .main)
    }

    var isInUse: Bool {
        if let devices = try? AudioHardwareSystem.shared.devices {
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
        }
        let processes = (try? AudioHardwareSystem.shared.processes) ?? []
        return processes.contains(where: usesRunningMicrophone)
    }

    private func usesRunningMicrophone(_ process: AudioHardwareProcess) -> Bool {
        // CoreSpeech can still report running input after dictation releases the mic.
        // Check the devices used for input so headset playback alone can't keep the timer paused.
        guard (try? process.isRunningInput) == true,
              let data = try? process.propertyData(address: inputDevices) else { return false }
        var ids = [AudioObjectID](repeating: 0, count: data.count / MemoryLayout<AudioObjectID>.stride)
        _ = ids.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return ids.contains { (try? AudioHardwareDevice(id: $0).isRunningInAProcess) == true }
    }
}
