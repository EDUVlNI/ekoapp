import AppKit
import CoreWLAN
import IOKit.ps
import IOBluetooth
import CoreAudio

enum StatusElement: String, CaseIterable {
    case time, wifi, battery, siri, bluetooth, headphones, music
    var title: String {
        switch self {
        case .time: return "Hora"
        case .wifi: return "Wi-Fi"
        case .battery: return "Bateria"
        case .siri: return "Siri"
        case .bluetooth: return "Bluetooth"
        case .headphones: return "Fones"
        case .music: return "Música"
        }
    }
    static let orders: [[StatusElement]] = [
        [.time, .wifi, .battery], [.time, .battery, .wifi],
        [.wifi, .battery, .time], [.wifi, .time, .battery],
        [.battery, .time, .wifi], [.battery, .wifi, .time]
    ]
}

enum MusicMetadataSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Esquerda" : "Direita" }
}

@MainActor
final class StatusModel: NSObject, ObservableObject {
    struct PowerState: Equatable {
        var level: Double = 0
        var hasBattery = false
        var charging = false
        var connected = false
        var lowPower = false

        static func from(_ description: [String: Any], lowPower: Bool) -> PowerState {
            let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue ?? 0
            let ratio = current / maximum
            return PowerState(level: ratio.isFinite ? min(1, max(0, ratio)) : 0,
                              hasBattery: true,
                              charging: (description[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue ?? false,
                              connected: (description[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue,
                              lowPower: lowPower)
        }
    }
    @Published var scale = StatusModel.bounded(UserDefaults.standard.object(forKey: "CapsuleScale") as? Double ?? 1, range: 0.75...1.6, fallback: 1) {
        didSet { UserDefaults.standard.set(scale, forKey: "CapsuleScale") }
    }
    @Published var backgroundOpacity = StatusModel.bounded(UserDefaults.standard.object(forKey: "CapsuleOpacity") as? Double ?? 0.92, range: 0...1, fallback: 0.92) {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "CapsuleOpacity") }
    }
    @Published var musicMetadataSide = MusicMetadataSide(rawValue: UserDefaults.standard.string(forKey: "MusicMetadataSide") ?? "right") ?? .right {
        didSet { UserDefaults.standard.set(musicMetadataSide.rawValue, forKey: "MusicMetadataSide") }
    }
    static func bounded(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    @Published var elements: [StatusElement] = {
        if let saved = UserDefaults.standard.stringArray(forKey: "ElementOrderV4") {
            let items = saved.compactMap(StatusElement.init(rawValue:))
            if Set(items).count == items.count && !items.isEmpty { return items }
        }
        if let oldItems = UserDefaults.standard.stringArray(forKey: "ElementOrder") {
            let migrated = oldItems.compactMap(StatusElement.init(rawValue:))
            if Set(migrated).count == 3 { return migrated + [.headphones] }
        }
        let old = UserDefaults.standard.integer(forKey: "StatusOrder")
        return (StatusElement.orders.indices.contains(old) ? StatusElement.orders[old] : StatusElement.orders[0]) + [.headphones]
    }() {
        didSet { UserDefaults.standard.set(elements.map { $0.rawValue }, forKey: "ElementOrderV4") }
    }
    @Published var showsPercentage = (UserDefaults.standard.object(forKey: "ShowsPercentage") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showsPercentage, forKey: "ShowsPercentage") }
    }
    @Published var showsPercentageWhileCharging = UserDefaults.standard.bool(forKey: "ShowsPercentageWhileCharging") {
        didSet { UserDefaults.standard.set(showsPercentageWhileCharging, forKey: "ShowsPercentageWhileCharging") }
    }
    var effectiveShowsPercentage: Bool {
        Self.shouldShowPercentage(manual: showsPercentage, automatic: showsPercentageWhileCharging, charging: isConnectedToPower)
    }
    static func shouldShowPercentage(manual: Bool, automatic: Bool, charging: Bool) -> Bool {
        manual || (automatic && charging)
    }
    @Published private(set) var timeText = "--:--"
    @Published private(set) var powerState = PowerState()
    var batteryLevel: Double { powerState.level }
    var hasBattery: Bool { powerState.hasBattery }
    var isCharging: Bool { powerState.charging }
    var isConnectedToPower: Bool { powerState.connected }
    var isLowPowerMode: Bool { powerState.lowPower }
    @Published private(set) var isWiFiConnected = false
    @Published private(set) var bluetoothOn = false
    @Published private(set) var headphoneName: String?
    @Published private(set) var freeClipConnected = false
    @Published var isPresented = false
    weak var siriHitView: NSView?
    weak var contentHitView: NSView?

    func setElement(_ element: StatusElement, enabled: Bool) {
        if enabled && element == .music { MediaRemoteWrapper.shared.enabled = true }
        if enabled && !elements.contains(element) {
            elements.append(element)
        }
        if !enabled { elements.removeAll { $0 == element } }
    }

    func activateSiri() {
        let url = URL(fileURLWithPath: "/System/Applications/Siri.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Não foi possível abrir a Siri"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var powerObserver: NSObjectProtocol?
    private var powerReader: (() -> PowerState?)?

    override init() { super.init() }
    init(powerReader: @escaping () -> PowerState?) {
        self.powerReader = powerReader
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<StatusModel>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in model.refreshPower() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        installPowerObserver()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        powerObserver = nil
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        refresh()
    }

    private func refresh() {
        timeText = clockFormatter.string(from: Date())

        if let interface = CWWiFiClient.shared().interface() {
            isWiFiConnected = interface.powerOn() && interface.serviceActive()
        } else {
            isWiFiConnected = false
        }
        refreshBattery()
        refreshAccessories()
    }

    private func refreshAccessories() {
        guard elements.contains(.bluetooth) || elements.contains(.headphones) else { return }
        bluetoothOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        guard elements.contains(.headphones) else { return }
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        let freeClip = devices.first { Self.isFreeClip($0.name ?? "") }
        // Audio/video major class + headset, hands-free or headphones minor class.
        let headset = devices.first {
            let major = ($0.classOfDevice >> 8) & 0x1f
            let minor = ($0.classOfDevice >> 2) & 0x3f
            return major == 4 && [1, 2, 6].contains(minor)
        }
        let active = activeHeadphones()
        let mapped = AudioDeviceManager.shared.isFreeClipActive
        let name = mapped ? AudioDeviceManager.shared.currentDeviceName : (freeClip?.name ?? active ?? headset?.name)
        if headphoneName != name { headphoneName = name }
        let isFreeClip = mapped || (name.map(Self.isFreeClip) ?? false)
        if freeClipConnected != isFreeClip { freeClipConnected = isFreeClip }
    }

    static func isFreeClip(_ name: String) -> Bool {
        name.lowercased().filter { $0.isLetter || $0.isNumber }.contains("freeclip")
    }

    private func activeHeadphones() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        let text = name.takeRetainedValue() as String
        if Self.isFreeClip(text) { return text }
        if ["headphone", "headset", "airpods", "fone"].contains(where: { text.lowercased().contains($0) }) { return text }
        address.mSelector = kAudioDevicePropertyDataSource
        address.mScope = kAudioDevicePropertyScopeOutput
        var source: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr && source == 0x6864706e { return "Fones de ouvido" }
        return nil
    }

    func installPowerObserver() {
        guard powerObserver == nil else { return }
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
            // Power notifications may arrive on a background thread. Always enqueue
            // rather than modifying SwiftUI state synchronously from the callback.
            Task { @MainActor [weak self] in self?.refreshPower() }
        }
    }

    private func refreshPower() {
        refreshBattery()
    }

    func applyPowerState(_ state: PowerState) {
        precondition(Thread.isMainThread, "Power state must be published on the main thread")
        if powerState != state { powerState = state }
    }

    private func refreshBattery() {
        if let powerReader {
            if let state = powerReader() { applyPowerState(state) }
            return
        }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType
            else { continue }

            let state = PowerState.from(description, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            applyPowerState(state)
            return
        }
        // A power-source snapshot can briefly be empty while the charger changes.
        // Keep the previous valid reading and retry on the next event/timer tick.
    }
}
