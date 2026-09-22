import Foundation
import CoreFoundation
typealias AudioDeviceID = UInt32
typealias Float32 = Float
let noErr: Int32 = 0
let kAudioHardwareServiceDeviceProperty_VirtualMainVolume = 0
let kAudioDevicePropertyScopeOutput = 0
let kAudioObjectPropertyElementMain = 0
struct AudioObjectPropertyAddress { var mSelector: Int; var mScope: Int; var mElement: Int }
let lock = NSLock()
var writes: [Float] = []
func AudioObjectIsPropertySettable(_ d: UInt32, _ a: inout AudioObjectPropertyAddress, _ result: inout DarwinBoolean) -> Int32 { result = true; return 0 }
func AudioObjectSetPropertyData(_ d: UInt32, _ a: inout AudioObjectPropertyAddress, _ q: Int, _ ptr: UnsafeRawPointer?, _ size: UInt32, _ value: inout Float) -> Int32 {
    precondition(!Thread.isMainThread, "Bluetooth writes must not block UI")
    Thread.sleep(forTimeInterval: 0.08)
    lock.lock(); writes.append(value); lock.unlock()
    return 0
}
final class Manager {
    var volumeAddress = AudioObjectPropertyAddress(mSelector: 0, mScope: 0, mElement: 0)
    var onVolumeChange: ((Double) -> Void)?
    var eventTapError: String?
    func getDefaultAudioOutputDevice() -> UInt32? { 42 }
    private let volumeQueue = DispatchQueue(label: "app.volume", qos: .userInteractive)
    private var pendingVolume: (AudioDeviceID, Double)?
    private var volumeWriteInFlight = false
    private var volumeReadInFlight = false
    private var volumeReadPending = false
    private var volumeRevision: UInt64 = 0
    private var lastVolumeWrite = Date.distantPast
    private var displayedVolume: Double?

    @discardableResult
    func setVolume(_ level: Double) -> Bool {
        guard level.isFinite, let device = getDefaultAudioOutputDevice() else { return false }
        var address = volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        let value = min(1, max(0, level))
        volumeRevision &+= 1
        pendingVolume = (device, value)
        displayedVolume = value
        onVolumeChange?(value)
        drainVolumeWrites()
        return true
    }

    private func drainVolumeWrites() {
        guard !volumeWriteInFlight, let (device, level) = pendingVolume else { return }
        pendingVolume = nil
        volumeWriteInFlight = true
        volumeQueue.async {
            var value = Float32(level)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            let result = AudioObjectSetPropertyData(device, &address, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &value)
            DispatchQueue.main.async {
                self.volumeWriteInFlight = false
                self.lastVolumeWrite = Date()
                if result != noErr {
                    self.eventTapError = "Não foi possível ajustar o volume deste dispositivo."
                    self.displayedVolume = nil
                }
                self.drainVolumeWrites()
            }
        }
    }



}
let manager = Manager()
var lastUI: Double = -1
manager.onVolumeChange = { value in precondition(Thread.isMainThread); lastUI = value }
let start = Date()
for i in 0...200 { precondition(manager.setVolume(Double(i) / 200)) }
precondition(Date().timeIntervalSince(start) < 0.1, "UI blocked behind writes")
precondition(lastUI == 1, "Slider did not immediately reach latest request")
precondition(!manager.setVolume(.nan))
let until = Date().addingTimeInterval(0.5)
while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
lock.lock(); let captured = writes; lock.unlock()
precondition(captured.count == 2, "Expected first and most recent write, got \(captured.count)")
precondition(captured.last == 1, "Final volume was lost")
print("PASS: 201 rapid slider values coalesced to two Bluetooth writes; latest value preserved; UI never blocked; NaN rejected")
