import Foundation
import CoreAudio
import AudioToolbox

final class AudioDeviceMonitor {
    var onSnapshotChanged: ((AudioDeviceSnapshot) -> Void)?

    private(set) var snapshot: AudioDeviceSnapshot?
    private let callbackQueue = DispatchQueue.main
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var observedDeviceID = AudioDeviceID(kAudioObjectUnknown)

    init() {
        installDefaultOutputListener()
        refresh()
    }

    deinit {
        removeDeviceListeners()
        if let block = defaultOutputListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                callbackQueue,
                block
            )
        }
    }

    func refresh() {
        guard let deviceID = currentDefaultOutputDeviceID() else {
            snapshot = nil
            return
        }

        if observedDeviceID != deviceID {
            observedDeviceID = deviceID
            installDeviceListeners(deviceID: deviceID)
        }

        let newSnapshot = AudioDeviceSnapshot(
            id: deviceID,
            name: deviceName(deviceID) ?? "Unknown Output",
            transportType: uint32Property(deviceID, selector: kAudioDevicePropertyTransportType),
            dataSource: uint32Property(
                deviceID,
                selector: kAudioDevicePropertyDataSource,
                scope: kAudioDevicePropertyScopeOutput
            ),
            isRunning: boolProperty(deviceID, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) ?? false,
            volume: outputVolume(deviceID)
        )

        snapshot = newSnapshot
        onSnapshotChanged?(newSnapshot)
    }

    func debugDescription() -> String {
        guard let snapshot else { return "No default output device" }
        let volume = Formatters.volume(snapshot.volume)
        return [
            "device: \(snapshot.name)",
            "id: \(snapshot.id)",
            "transport: \(fourCharString(snapshot.transportType))",
            "dataSource: \(fourCharString(snapshot.dataSource))",
            "headphones: \(snapshot.isHeadphone)",
            "running: \(snapshot.isRunning)",
            "volume: \(volume)"
        ].joined(separator: "\n")
    }

    private func installDefaultOutputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()
        }
        defaultOutputListener = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            block
        )
    }

    private func installDeviceListeners(deviceID: AudioDeviceID) {
        removeDeviceListeners()

        let addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
        ]

        for baseAddress in addresses {
            var address = baseAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.refresh()
            }

            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &address,
                callbackQueue,
                block
            )

            if status == noErr {
                deviceListeners.append((deviceID, baseAddress, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for (deviceID, baseAddress, block) in deviceListeners {
            var address = baseAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, callbackQueue, block)
        }
        deviceListeners.removeAll()
    }

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name as String
    }

    private func uint32Property(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func boolProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool? {
        uint32Property(deviceID, selector: selector, scope: scope).map { $0 != 0 }
    }

    private func float32Property(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    private func outputVolume(_ deviceID: AudioDeviceID) -> Double? {
        if let value = float32Property(
            deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return Double(value)
        }

        if let value = float32Property(
            deviceID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return Double(value)
        }

        let channelVolumes = [1, 2].compactMap {
            float32Property(
                deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement($0)
            )
        }
        guard !channelVolumes.isEmpty else { return nil }
        return Double(channelVolumes.reduce(0, +) / Float32(channelVolumes.count))
    }
}
