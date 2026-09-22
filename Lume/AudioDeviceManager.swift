import AppKit
import Foundation
import CoreAudio

class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var currentDeviceName = ""
    @Published var isFreeClipActive: Bool = false
    @Published var isHeadphonesActive = false
    private var connectionTimer: Timer?

    private var defaultOutputDeviceID: AudioDeviceID = kAudioObjectUnknown

    private init() {
        checkCurrentDevice()
        setupListener()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkCurrentDevice() }
        RunLoop.main.add(timer, forMode: .common)
        connectionTimer = timer
    }

    private func setupListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerBlock,
            selfPtr
        )
    }

    private let listenerBlock: AudioObjectPropertyListenerProc = { objectID, numberAddresses, addresses, clientData in
        if let clientData = clientData {
            let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.checkCurrentDevice()
            }
        }
        return noErr
    }

    func checkCurrentDevice() {
        var defaultOutputDevice: AudioDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDevice
        )

        if status == noErr && defaultOutputDevice != kAudioObjectUnknown {
            var aliveAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var alive: UInt32 = 0
            var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(defaultOutputDevice, &aliveAddress, 0, nil, &aliveSize, &alive) == noErr, alive != 0 else { resetOutput(); return }
            self.defaultOutputDeviceID = defaultOutputDevice
            let uid = getDeviceUID(deviceID: defaultOutputDevice)
            let name = getDeviceName(deviceID: defaultOutputDevice)
            currentDeviceName = name

            let storedUID = UserDefaults.standard.string(forKey: "freeClipDeviceUID")
            let matchesUID = !uid.isEmpty && uid == storedUID
            let matchesName = !name.isEmpty && name.lowercased().contains("freeclip")

            var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(defaultOutputDevice, &transportAddress, 0, nil, &size, &transport)
            let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            // Never let a stale manual mapping turn the Mac speakers into FreeClip.
            isFreeClipActive = bluetooth && (matchesUID || matchesName)
            var sourceAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var source: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(defaultOutputDevice, &sourceAddress, 0, nil, &size, &source)
            isHeadphonesActive = isFreeClipActive || source == 0x6864706e || ["headphone", "headset", "airpods", "fone"].contains(where: name.lowercased().contains)
        } else { resetOutput() }
    }

    private func resetOutput() {
        defaultOutputDeviceID = kAudioObjectUnknown
        currentDeviceName = ""
        isFreeClipActive = false
        isHeadphonesActive = false
    }

    func clearFreeClipAssociation() {
        UserDefaults.standard.removeObject(forKey: "freeClipDeviceUID")
        checkCurrentDevice()
    }

    func associateCurrentDeviceAsFreeClip() {
        let uid = getDeviceUID(deviceID: defaultOutputDeviceID)
        if !uid.isEmpty {
            UserDefaults.standard.set(uid, forKey: "freeClipDeviceUID")
            checkCurrentDevice()
        }
    }

    func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        )
        return status == noErr ? (name?.takeRetainedValue() as String? ?? "") : ""
    }

    func getDeviceUID(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &uid
        )
        return status == noErr ? (uid?.takeRetainedValue() as String? ?? "") : ""
    }
}
