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
        // Device changes tell us when to check. Per-process input activity distinguishes
        // microphone use from output playing through the same headset.
        let processes = (try? AudioHardwareSystem.shared.processes) ?? []
        return processes.contains { (try? $0.isRunningInput) == true }
    }
}
