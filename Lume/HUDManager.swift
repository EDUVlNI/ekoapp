import AppKit
import SwiftUI
import IOKit.graphics
import CoreAudio
import AudioToolbox

class HUDManager: ObservableObject {
    @Published var selectedStyle: HUDStyle = .iOSVolume {
        didSet {
            UserDefaults.standard.set(selectedStyle.rawValue, forKey: "HUDStyle")
        }
    }

    private var hudWindow: NSPanel?

    static let shared = HUDManager()

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "HUDStyle"), let style = HUDStyle(rawValue: saved) {
            self.selectedStyle = style
        }
    }

    private var hideWorkItem: DispatchWorkItem?
    private var presentationGeneration: UInt64 = 0
    private var isInteracting = false

    func showPreview() {
        showHUD(style: selectedStyle, value: 0.8)
    }

    func showVolume(_ volume: Double) {
        showHUD(style: .iOSVolume, value: volume)
    }

    func showDisplayBrightness(_ brightness: Double) {
        showHUD(style: .iOSDisplay, value: brightness)
    }

    func showKeyboardBrightness(_ brightness: Double) {
        showHUD(style: .iOSKeyboard, value: brightness)
    }

    func hideNowPlaying() {
        guard HUDState.shared.style == .nowPlayingClassic else { return }
        presentationGeneration &+= 1
        hideWorkItem?.cancel()
        HUDState.shared.hide()
        hudWindow?.orderOut(nil)
    }

    func stop() {
        presentationGeneration &+= 1
        hideWorkItem?.cancel()
        hudWindow?.orderOut(nil)
        hudWindow = nil
    }

    func showNowPlaying() {
        showHUD(style: .nowPlayingClassic, value: 0)
    }

    private func showHUD(style: HUDStyle, value: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard value.isFinite else { return }
        if isInteracting && HUDState.shared.style != style { return }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        if hudWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            // Atribui a view apenas UMA vez
            let view = HUDView()
            window.contentView = NSHostingView(rootView: view)

            hudWindow = window
        }

        guard let window = hudWindow else { return }

        // Cancelar animação de esconder anterior se existir
        hideWorkItem?.cancel()

        HUDState.shared.setLevel = style == .iOSVolume ? { level in
            _ = MediaKeyManager.shared.setVolume(level)
        } : style == .iOSDisplay ? { level in
            _ = MediaKeyManager.shared.setBrightness(level)
        } : style == .iOSKeyboard ? { level in
            _ = MediaKeyManager.shared.setKeyboardBrightness(level)
        } : nil
        HUDState.shared.editing = { [weak self] active in
            guard let self = self else { return }
            self.isInteracting = active
            if active { self.hideWorkItem?.cancel() }
            else { self.showHUD(style: HUDState.shared.style, value: HUDState.shared.value) }
        }
        // Atualiza os valores via Estado Global (HUDState)
        HUDState.shared.show(style: style, value: value, animateLevel: false)

        // Redimensionar a janela para acomodar as animações vindas de fora da tela
        let contentSize = style == .nowPlayingClassic ? NSSize(width: 450, height: 200) : NSSize(width: 200, height: 300)
        if window.contentView?.frame.size != contentSize { window.setContentSize(contentSize) }

        // Posicionar ancorado exatamente na borda da tela
        if let screen = NSScreen.main {
            var x: CGFloat = screen.frame.midX - window.frame.width / 2
            var y: CGFloat = screen.frame.midY - window.frame.height / 2

            if style != .nowPlayingClassic {
                // Colado na borda esquerda
                x = screen.frame.minX
                y = screen.frame.midY - window.frame.height / 2
            } else if style == .nowPlayingClassic {
                // Colado no topo da tela
                y = screen.frame.maxY - window.frame.height
            }

            let origin = NSPoint(x: x, y: y)
            if window.frame.origin != origin { window.setFrameOrigin(origin) }
        }

        window.alphaValue = 1.0
        if !window.isVisible { window.orderFront(nil) }

        // Criar novo timer para esconder (aumentado para 3 segundos para Touch Bar e evitar fechar rápido)
        let hideTask = DispatchWorkItem { [weak self] in
            guard let self = self, self.presentationGeneration == generation, !self.isInteracting else { return }
            HUDState.shared.hide()

            // Remover fisicamente a janela depois que a SwiftUI fechar (0.5s depois)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.presentationGeneration == generation else { return }
                self.hudWindow?.orderOut(nil)
            }
        }

        self.hideWorkItem = hideTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3, execute: hideTask)
    }
}

class MediaKeyManager: ObservableObject {
    private var isMonitoring = false
    fileprivate var eventPort: CFMachPort?
    fileprivate var runLoopSource: CFRunLoopSource?

    static let shared = MediaKeyManager()

    var onVolumeChange: ((Double) -> Void)?

    @Published var isAccessibilityGranted = false

    func checkAccessibility(prompt: Bool) {
        isMonitoring = true
        let granted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            granted = AXIsProcessTrustedWithOptions(options)
        } else {
            granted = AXIsProcessTrusted()
        }

        DispatchQueue.main.async {
            guard self.isMonitoring else { return }
            self.isAccessibilityGranted = granted
            self.addAudioListener()
            self.startPollingBrightness()
            if !granted { self.stopEventTap() }
            if granted && self.eventPort == nil {
                self.startIntercepting()
            }
        }
    }





    private var observedDevice: AudioDeviceID?
    private var observingDefaultDevice = false
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private let audioListenerCallback: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData = clientData else { return noErr }
        let manager = Unmanaged<MediaKeyManager>.fromOpaque(clientData).takeUnretainedValue()
        DispatchQueue.main.async {
            guard manager.isMonitoring else { return }
            manager.addAudioListener()
            manager.refreshObservedVolume()
        }
        return noErr
    }

    private let keyboardBacklight = KeyboardBacklight()
    private let displayBacklight = DisplayBacklight()
    private var lastKeyboardBrightness: Double?
    private var brightnessTimer: Timer?
    private var lastBrightness: Float = -1.0

    private lazy var brightnessEvents = BrightnessEvents()
    private var displayChangeGeneration: UInt64 = 0
    private var keyboardChangeGeneration: UInt64 = 0
    private var lastKeyboardManualLevel: Double?
    private var lastDisplayManualLevel: Double?
    private var lastDisplayEvent: (time: TimeInterval, value: Double, automatic: Bool)?
    private var lastKeyboardSliderEvent: TimeInterval = -.infinity

    private func startPollingBrightness() {
        guard brightnessTimer == nil else { return }
        lastKeyboardBrightness = keyboardBacklight.read()
        lastKeyboardManualLevel = brightnessEvents.keyboardManualLevel(id: keyboardBacklight.id)
        lastBrightness = Float(displayBacklight.read() ?? -1)
        lastDisplayManualLevel = brightnessEvents.displayManualLevel(display: displayBacklight.displayID)
        brightnessEvents.start(display: displayBacklight.displayID, keyboard: keyboardBacklight.id,
            displayChanged: { [weak self] value, automatic in
                guard let self = self else { return }
                guard !self.displayWrites.isBusy else { return }
                self.lastDisplayEvent = (ProcessInfo.processInfo.systemUptime, value, automatic)
                self.displayChangeGeneration &+= 1
                // UserBrightness signals intent but is not necessarily in the
                // normalized DisplayServices scale used by the slider/setter.
                if let normalized = self.displayBacklight.read() {
                    self.lastBrightness = Float(normalized)
                    if !automatic { self.onDisplayBrightnessChange?(normalized) }
                }
            }, keyboardSliderChanged: { [weak self] value in
                guard let self = self else { return }
                guard !self.keyboardWrites.isBusy else { return }
                self.lastKeyboardSliderEvent = ProcessInfo.processInfo.systemUptime
                self.keyboardChangeGeneration &+= 1
                self.lastKeyboardBrightness = value
                if !self.keyboardWrites.isBusy { self.onKeyboardBrightnessChange?(value) }
            })
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollBrightness()
        }
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    private func pollBrightness() {
        let now = ProcessInfo.processInfo.systemUptime
        // Observe the user's slider position independently of the final display
        // state notification. Ambient changes must not be inferred as gestures.
        if !displayWrites.isBusy {
            let manual = brightnessEvents.displayManualLevel(display: displayBacklight.displayID)
            if BrightnessChangePolicy.manualValueChanged(lastDisplayManualLevel, manual),
               let normalized = displayBacklight.read() {
                lastBrightness = Float(normalized)
                onDisplayBrightnessChange?(normalized)
            }
            lastDisplayManualLevel = manual
        }
        // A level change alone has no provenance: only explicit manual events
        // and our own setters are permitted to present the display HUD.
        if !displayWrites.isBusy, let value = displayBacklight.read() {
            lastBrightness = Float(value)
        }
        if !keyboardWrites.isBusy, let value = keyboardBacklight.read() {
            let previous = lastKeyboardBrightness
            let manual = brightnessEvents.keyboardManualLevel(id: keyboardBacklight.id)
            let manualChanged = BrightnessChangePolicy.manualValueChanged(lastKeyboardManualLevel, manual)
            lastKeyboardBrightness = value
            lastKeyboardManualLevel = manual
            guard let previous = previous, abs(value - previous) > 0.001 else { return }
            let automaticEnabled = keyboardBacklight.autoBrightnessEnabled
            let dimmed = keyboardBacklight.isIdleDimmed
            let explicitSlider = now - lastKeyboardSliderEvent < 0.3
            let show = BrightnessChangePolicy.showKeyboardChange(
                manualChanged: manualChanged, hasManualValue: manual != nil,
                automaticEnabled: automaticEnabled, idleDimmed: dimmed,
                explicitSlider: explicitSlider)
            if show { onKeyboardBrightnessChange?(value) }
        }
    }

    private func addAudioListener() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if !observingDefaultDevice {
            observingDefaultDevice = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                &defaultAddress, audioListenerCallback, context) == noErr
        }
        let next = getDefaultAudioOutputDevice()
        guard observedDevice != next else { return }
        displayedVolume = nil
        pendingVolume = nil
        volumeRevision &+= 1
        if let old = observedDevice {
            AudioObjectRemovePropertyListener(old, &volumeAddress, audioListenerCallback, context)
            AudioObjectRemovePropertyListener(old, &muteAddress, audioListenerCallback, context)
        }
        observedDevice = nil
        guard let device = next else { return }
        let volumeStatus = AudioObjectAddPropertyListener(device, &volumeAddress, audioListenerCallback, context)
        let muteStatus = AudioObjectAddPropertyListener(device, &muteAddress, audioListenerCallback, context)
        if volumeStatus == noErr || muteStatus == noErr { observedDevice = device }
    }

    private func startIntercepting() {
        addAudioListener()
        startPollingBrightness()
        let eventMask: CGEventMask = 1 << 14 // Only system-defined media keys.

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            eventTapError = "Não foi possível iniciar as teclas de mídia. Verifique a autorização e tente novamente."
            return
        }

        eventTapError = nil
        eventPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    @Published var eventTapError: String?

    private func stopEventTap() {
        if let port = eventPort { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port = eventPort { CFMachPortInvalidate(port) }
        runLoopSource = nil
        eventPort = nil
        consumedKeys.removeAll()
    }

    func stop() {
        stopEventTap()
        displayWrites.cancelPending()
        keyboardWrites.cancelPending()
        isMonitoring = false
        pendingVolume = nil
        displayedVolume = nil
        volumeRevision &+= 1
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        brightnessEvents.stop()
        displayChangeGeneration &+= 1
        keyboardChangeGeneration &+= 1
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let device = observedDevice {
            AudioObjectRemovePropertyListener(device, &volumeAddress, audioListenerCallback, context)
            AudioObjectRemovePropertyListener(device, &muteAddress, audioListenerCallback, context)
        }
        if observingDefaultDevice {
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, audioListenerCallback, context)
        }
        observedDevice = nil
        observingDefaultDevice = false
    }


    private var consumedKeys = Set<Int>()

    private let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<MediaKeyManager>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = manager.eventPort {
                // Re-ativa o tap de forma assíncrona para não travar o loop
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == 14 { // NX_SYSDEFINED
            if let nsEvent = NSEvent(cgEvent: event) {
                if nsEvent.subtype.rawValue == 8 {
                    let data1 = nsEvent.data1
                    let keyCode = (data1 & 0xFFFF0000) >> 16
                    let keyFlags = (data1 & 0x0000FFFF)
                    let keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA

                    // A Touch Bar manda dezenas de eventos por segundo,
                    // então usamos uma fila serial para não atropelar as chamadas do CoreAudio
                    if keyState {
                    if keyCode == 0 {
                        if manager.changeVolume(by: 0.05) { manager.consumedKeys.insert(keyCode); return nil }
                        return Unmanaged.passUnretained(event)
                    } else if keyCode == 1 {
                        if manager.changeVolume(by: -0.05) { manager.consumedKeys.insert(keyCode); return nil }
                        return Unmanaged.passUnretained(event)
                    } else if keyCode == 7 {
                        if manager.toggleMute() { manager.consumedKeys.insert(keyCode); return nil }
                        return Unmanaged.passUnretained(event)
                    } else if keyCode == 2 {
                        if manager.changeBrightness(by: 0.06) { manager.consumedKeys.insert(keyCode); return nil }
                        return Unmanaged.passUnretained(event)
                    } else if keyCode == 3 {
                        if manager.changeBrightness(by: -0.06) { manager.consumedKeys.insert(keyCode); return nil }
                        return Unmanaged.passUnretained(event)
                    } else if keyCode == 21 || keyCode == 22 {
                        if let current = manager.keyboardBacklight.read(),
                           manager.setKeyboardBrightness(current + (keyCode == 21 ? 0.0625 : -0.0625)) {
                            manager.consumedKeys.insert(keyCode)
                            return nil
                        }
                        return Unmanaged.passUnretained(event)
                    }

                } else {
                    if manager.consumedKeys.remove(keyCode) != nil { return nil }

                }
            }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func getDefaultAudioOutputDevice() -> AudioDeviceID? {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        var getDefaultOutputDevicePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getDefaultOutputDevicePropertyAddress,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )

        return status == noErr ? defaultOutputDeviceID : nil
    }

    private let volumeQueue = DispatchQueue(label: "app.volume", qos: .userInteractive)
    private var pendingVolume: (AudioDeviceID, Double)?
    private var volumeWriteInFlight = false
    private var volumeReadInFlight = false
    private var volumeReadPending = false
    private var volumeRevision: UInt64 = 0
    private var lastVolumeWrite = Date.distantPast
    private var displayedVolume: Double?

    private func refreshObservedVolume() {
        if volumeReadInFlight { volumeReadPending = true; return }
        guard !volumeReadInFlight, !volumeWriteInFlight, pendingVolume == nil,
              Date().timeIntervalSince(lastVolumeWrite) > 0.25 else { return }
        let revision = volumeRevision
        volumeReadInFlight = true
        volumeQueue.async {
            let value = self.getSystemVolume()
            DispatchQueue.main.async {
                self.volumeReadInFlight = false
                defer {
                    if self.volumeReadPending {
                        self.volumeReadPending = false
                        self.refreshObservedVolume()
                    }
                }
                guard revision == self.volumeRevision, !self.volumeWriteInFlight,
                      let value = value else { return }
                let changed = self.displayedVolume.map { abs($0 - value) > 0.0001 } ?? true
                self.displayedVolume = value
                // A Control Strip drag cannot be consumed by a media-key event tap.
                // Show our observer HUD only while the native helper is confirmed paused.
                if changed && NativeHUDController.shared.isSuppressing {
                    self.onVolumeChange?(value)
                }
            }
        }
    }

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

    private let displayWrites = LatestLevelWriter()
    private let keyboardWrites = LatestLevelWriter()

    @discardableResult
    func setBrightness(_ level: Double) -> Bool {
        guard level.isFinite, displayBacklight.canWrite else { return false }
        let value = min(1, max(0, level))
        let displayID = displayBacklight.displayID
        displayChangeGeneration &+= 1
        lastBrightness = Float(value)
        onDisplayBrightnessChange?(value)
        displayWrites.submit(value, write: { [displayBacklight] value in
            displayBacklight.set(value, displayID: displayID)
        }, completion: { [weak self] success in
            if !success { self?.eventTapError = "Não foi possível ajustar o brilho desta tela." }
        })
        return true
    }

    private func changeVolume(by amount: Double) -> Bool {
        guard let current = displayedVolume ?? getSystemVolume() else { return false }
        return setVolume(current + amount)
    }

    private func toggleMute() -> Bool {
        guard let device = getDefaultAudioOutputDevice() else { return false }

        var mute: UInt32 = 0
        var muteSize = UInt32(MemoryLayout.size(ofValue: mute))
        var mutePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectGetPropertyData(device, &mutePropertyAddress, 0, nil, &muteSize, &mute) != noErr {
            return false
        }

        mute = (mute == 0) ? 1 : 0
        if AudioObjectSetPropertyData(device, &mutePropertyAddress, 0, nil, muteSize, &mute) == noErr {
            let currentVolume = getSystemVolume()
            DispatchQueue.main.async {
                if let currentVolume = currentVolume { self.onVolumeChange?(currentVolume) }
            }
            return true
        }
        return false
    }

    private func getSystemVolume() -> Double? {
        guard let device = getDefaultAudioOutputDevice() else { return nil }
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted) == noErr, muted != 0 { return 0 }

        var volume: Float32 = 0.0
        var volumeSize = UInt32(MemoryLayout.size(ofValue: volume))
        var volumePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(device, &volumePropertyAddress, 0, nil, &volumeSize, &volume) == noErr, volume.isFinite else { return nil }
        return Double(min(1, max(0, volume)))
    }

    var onDisplayBrightnessChange: ((Double) -> Void)?
    var onKeyboardBrightnessChange: ((Double) -> Void)?

    @discardableResult
    func setKeyboardBrightness(_ level: Double) -> Bool {
        guard level.isFinite, keyboardBacklight.canWrite else { return false }
        let value = min(1, max(0, level))
        lastKeyboardBrightness = value
        lastKeyboardManualLevel = value
        lastKeyboardSliderEvent = ProcessInfo.processInfo.systemUptime
        onKeyboardBrightnessChange?(value)
        keyboardWrites.submit(value, write: { [keyboardBacklight] value in keyboardBacklight.set(value) }, completion: { [weak self] success in
            if !success { self?.eventTapError = "Não foi possível ajustar a iluminação do teclado." }
        })
        return true
    }

    private func changeBrightness(by amount: Double) -> Bool {
        if lastBrightness >= 0 { return setBrightness(Double(lastBrightness) + amount) }
        if let current = displayBacklight.read() { return setBrightness(current + amount) }
        let brightnessKey = "brightness" as CFString
        var iterator: io_iterator_t = 0
        var current: Float = 0.5
        var success = false

        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess {
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            if service != 0 {
                defer { IOObjectRelease(service) }
                if IODisplayGetFloatParameter(service, 0, brightnessKey, &current) == kIOReturnSuccess {
                    var newB = current + Float(amount)
                    if newB > 1.0 { newB = 1.0 }
                    if newB < 0.0 { newB = 0.0 }

                    if IODisplaySetFloatParameter(service, 0, brightnessKey, newB) == kIOReturnSuccess {
                        current = newB
                        success = true
                    }
                }
            }
        }

        if success {
            DispatchQueue.main.async {
                self.onDisplayBrightnessChange?(Double(current))
            }
        }
        return success
    }

}

/// Session-only experimental integration. The separate helper owns restoration.
final class NativeHUDController: ObservableObject {
    static let shared = NativeHUDController()
    @Published private(set) var enabled = false
    @Published private(set) var status = "Modo Touch Bar experimental desativado"
    private var process: Process?
    private var input: Pipe?
    private var heartbeat: DispatchSourceTimer?
    @Published private(set) var isSuppressing = false

    func setEnabled(_ value: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        if !value { stop(); return }
        guard process == nil else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == "MediaMate" }) {
            status = "Feche o MediaMate antes de ativar este modo."
            return
        }
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "OSDGuardian") else {
            status = "Componente da Touch Bar ausente nesta compilação."
            return
        }
        let child = Process()
        let pipe = Pipe()
        child.executableURL = executable
        child.standardInput = pipe
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let message = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self = self, self.process === child else { return }
                if message.contains("active") { self.isSuppressing = true; self.status = "Modo Touch Bar ativo — teste o arraste" }
                if message.contains("conflict") { self.status = "Indicador nativo já controlado por outro processo." }
                if message.contains("failed") { self.status = "O macOS não permitiu controlar o indicador nativo." }
            }
        }
        child.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self = self, self.process === ended else { return }
                self.heartbeat?.cancel()
                self.heartbeat = nil
                try? self.input?.fileHandleForWriting.close()
                self.input = nil
                self.process = nil
                self.enabled = false
                self.isSuppressing = false
                self.status = "Modo encerrado (código \(ended.terminationStatus))."
            }
        }
        do { try child.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            status = "Não foi possível iniciar o modo Touch Bar."
            return
        }
        process = child
        input = pipe
        enabled = true
        status = "Aguardando o indicador nativo; o primeiro ajuste pode exibi-lo."
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "app.guardian.heartbeat"))
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            do { try pipe.fileHandleForWriting.write(contentsOf: Data([1])) }
            catch { DispatchQueue.main.async { self?.stop() } }
        }
        heartbeat = timer
        timer.resume()
    }

    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        // EOF restores the native HUD even if the app exits immediately afterwards.
        try? input?.fileHandleForWriting.close()
        input = nil
        enabled = false
        isSuppressing = false
        status = "Modo Touch Bar desativado; restaurando indicador nativo."
    }
}

/// Origin classification is independent of presentation and is regression-tested.
enum BrightnessChangePolicy {
    static func isAutomaticDisplayReason(_ reason: String?) -> Bool {
        guard let reason = reason?.lowercased(), !reason.isEmpty else { return true }
        let automatic = ["auto", "ambient", "als", "idle", "magsafe", "thermal", "power"]
        if automatic.contains(where: reason.contains) { return true }
        return !["user", "manual", "slider", "key", "button", "control center"].contains(where: reason.contains)
    }
    static func manualValueChanged(_ previous: Double?, _ current: Double?) -> Bool {
        guard let current = current, current.isFinite else { return false }
        guard let previous = previous else { return false }
        return abs(previous - current) > 0.00001
    }
    static func showKeyboardChange(manualChanged: Bool, hasManualValue: Bool,
                                   automaticEnabled: Bool?, idleDimmed: Bool?, explicitSlider: Bool) -> Bool {
        if explicitSlider || manualChanged { return true }
        return false // No manual signal means the change must remain silent.
    }
}

/// Read-only CoreBrightness origin notifications. Never disables ambient adjustment.
final class BrightnessEvents {
    private let injectedClient: NSObject?
    init(client: NSObject? = nil) { injectedClient = client }
    private let library = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
    private lazy var client: NSObject? = injectedClient ?? (library == nil ? nil : (NSClassFromString("BrightnessSystemClient") as? NSObject.Type)?.init())
    private var displayID: UInt64?
    private var keyboardID: UInt64?
    private var generation: UInt64 = 0
    private let displayKeys = ["CBDisplayBrightnessState", "DisplayServicesUserBrightness"] as NSArray
    private let keyboardKeys = ["KeyboardBacklightBrightnessSlider"] as NSArray

    func keyboardManualLevel(id: UInt64?) -> Double? {
        let selector = NSSelectorFromString("copyPropertyForKey:keyboardID:")
        guard let client = client, let id = id, client.responds(to: selector) else { return nil }
        typealias Copy = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
        let copy = unsafeBitCast(client.method(for: selector), to: Copy.self)
        let object = copy(client, selector, "KeyboardBacklightManualBrightness", id)?.takeRetainedValue()
        guard let value = (object as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return value
    }

    func displayManualLevel(display: UInt32) -> Double? {
        let selector = NSSelectorFromString("copyPropertyForKey:andDisplay:")
        guard display != 0, let client, client.responds(to: selector) else { return nil }
        typealias Read = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
        let result = unsafeBitCast(client.method(for: selector), to: Read.self)(client, selector, "DisplayServicesUserBrightness", UInt64(display))?.takeRetainedValue()
        guard let value = (result as? NSNumber)?.doubleValue, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    func start(display: UInt32, keyboard: UInt64?,
               displayChanged: @escaping (Double, Bool) -> Void,
               keyboardSliderChanged: @escaping (Double) -> Void) {
        stop()
        guard let client = client else { return }
        let token = generation
        let displaySelector = NSSelectorFromString("registerDisplayNotificationCallbackBlock:")
        let keyboardSelector = NSSelectorFromString("registerKeyboardNotificationCallbackBlock:")
        typealias DisplayBlock = @convention(block) (NSString, UInt64, AnyObject?) -> Void
        typealias KeyboardBlock = @convention(block) (NSString, AnyObject?, UInt64) -> Void
        typealias RegisterDisplay = @convention(c) (AnyObject, Selector, DisplayBlock) -> Void
        typealias RegisterKeyboard = @convention(c) (AnyObject, Selector, KeyboardBlock) -> Void
        if client.responds(to: displaySelector), display != 0 {
            let block: DisplayBlock = { [weak self] key, id, object in
                if key as String == "DisplayServicesUserBrightness", id == UInt64(display),
                   let value = (object as? NSNumber)?.doubleValue, value.isFinite, (0...1).contains(value) {
                    DispatchQueue.main.async {
                        guard self?.generation == token else { return }
                        displayChanged(value, false)
                    }
                    return
                }
                guard key as String == "CBDisplayBrightnessState", id == UInt64(display),
                      let info = object as? [String: Any],
                      let number = info["DisplayServicesBrightness"] as? NSNumber else { return }
                let value = number.doubleValue
                guard value.isFinite, (0...1).contains(value) else { return }
                let automatic = BrightnessChangePolicy.isAutomaticDisplayReason(info["CBReasonForBrightnessChange"] as? String)
                DispatchQueue.main.async {
                    guard self?.generation == token else { return }
                    displayChanged(value, automatic)
                }
            }
            unsafeBitCast(client.method(for: displaySelector), to: RegisterDisplay.self)(client, displaySelector, block)
            register(keys: displayKeys, id: UInt64(display), selector: "registerNotificationForKeys:andDisplay:")
            displayID = UInt64(display)
        }
        if client.responds(to: keyboardSelector), let keyboard = keyboard {
            let block: KeyboardBlock = { [weak self] key, object, id in
                guard key as String == "KeyboardBacklightBrightnessSlider", id == keyboard,
                      let value = (object as? NSNumber)?.doubleValue,
                      value.isFinite, (0...1).contains(value) else { return }
                DispatchQueue.main.async {
                    guard self?.generation == token else { return }
                    keyboardSliderChanged(value)
                }
            }
            unsafeBitCast(client.method(for: keyboardSelector), to: RegisterKeyboard.self)(client, keyboardSelector, block)
            register(keys: keyboardKeys, id: keyboard, selector: "registerNotificationForKeys:keyboardID:")
            keyboardID = keyboard
        }
    }
    private func register(keys: NSArray, id: UInt64, selector name: String) {
        let selector = NSSelectorFromString(name)
        guard let client = client, client.responds(to: selector) else { return }
        typealias Register = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Void
        unsafeBitCast(client.method(for: selector), to: Register.self)(client, selector, keys, id)
    }
    func stop() {
        generation &+= 1
        if let id = displayID { register(keys: displayKeys, id: id, selector: "unregisterNotificationForKeys:andDisplay:") }
        if let id = keyboardID { register(keys: keyboardKeys, id: id, selector: "unregisterNotificationForKeys:keyboardID:") }
        for name in ["unregisterDisplayNotificationBlock", "unregisterKeyboardNotificationBlock"] {
            let selector = NSSelectorFromString(name)
            if let client = client, client.responds(to: selector) { _ = client.perform(selector) }
        }
        displayID = nil
        keyboardID = nil
    }
}

/// Optional runtime integration: unsupported systems fall through to macOS.
final class KeyboardBacklight {
    private let client: NSObject?
    private let library: UnsafeMutableRawPointer?
    private let readSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let writeSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private var keyboardID: UInt64?

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        client = library == nil ? nil : (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
        refreshKeyboard()
    }

    var id: UInt64? { if keyboardID == nil { refreshKeyboard() }; return keyboardID }
    private func readFlag(_ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard let client = client, let id = id, client.responds(to: selector) else { return nil }
        typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Int8
        return unsafeBitCast(client.method(for: selector), to: Read.self)(client, selector, id) != 0
    }
    var autoBrightnessEnabled: Bool? { readFlag("isAutoBrightnessEnabledForKeyboard:") }
    var isIdleDimmed: Bool? { readFlag("isBacklightDimmedOnKeyboard:") }

    private func refreshKeyboard() {
        let selector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let client = client, client.responds(to: selector),
              let ids = client.perform(selector)?.takeRetainedValue() as? [NSNumber] else { return }
        keyboardID = ids.first?.uint64Value
    }

    func read() -> Double? {
        guard let client = client, client.responds(to: readSelector) else { return nil }
        if keyboardID == nil { refreshKeyboard() }
        guard let id = keyboardID else { return nil }
        typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let call = unsafeBitCast(client.method(for: readSelector), to: Read.self)
        let value = call(client, readSelector, id)
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    var canWrite: Bool { keyboardID != nil && client?.responds(to: writeSelector) == true }
    func set(_ level: Double) -> Bool {
        guard level.isFinite, let client = client, let id = keyboardID,
              client.responds(to: writeSelector) else { return false }
        // Ventura's Objective-C encoding is c28@0:8f16Q20 (BOOL, float, uint64).
        typealias Write = @convention(c) (AnyObject, Selector, Float, UInt64) -> Int8
        let call = unsafeBitCast(client.method(for: writeSelector), to: Write.self)
        return call(client, writeSelector, Float(min(1, max(0, level))), id) != 0
    }
}

final class DisplayBacklight {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    var displayID: CGDirectDisplayID { display }
    private var display: CGDirectDisplayID {
        NSScreen.screens.first(where: { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0
        }).flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value } ?? CGMainDisplayID()
    }
    func read() -> Double? {
        guard let library = library, let symbol = dlsym(library, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = -1
        guard unsafeBitCast(symbol, to: Get.self)(display, &value) == 0,
              value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }
    var canWrite: Bool { library.flatMap { dlsym($0, "DisplayServicesSetBrightness") } != nil && display != 0 }
    func set(_ value: Double, displayID: UInt32) -> Bool {
        guard value.isFinite, let library = library, let symbol = dlsym(library, "DisplayServicesSetBrightness") else { return false }
        return unsafeBitCast(symbol, to: Set.self)(displayID, Float(min(1, max(0, value)))) == 0
    }
}

// Serial hardware writes never block the UI; intermediate drag values are coalesced.
final class LatestLevelWriter {
    private let queue = DispatchQueue(label: "lume.brightness", qos: .userInteractive)
    private var pending: (Double, (Double) -> Bool, (Bool) -> Void)?
    private(set) var isBusy = false
    private var generation: UInt64 = 0
    func cancelPending() { pending = nil; generation &+= 1 }
    func submit(_ level: Double, write: @escaping (Double) -> Bool, completion: @escaping (Bool) -> Void) {
        guard level.isFinite else { return }
        pending = (min(1, max(0, level)), write, completion)
        drain()
    }
    private func drain() {
        guard !isBusy, let request = pending else { return }
        pending = nil
        isBusy = true
        let token = generation
        queue.async {
            let success = request.1(request.0)
            DispatchQueue.main.async {
                self.isBusy = false
                if token == self.generation { request.2(success) }
                self.drain()
            }
        }
    }
}
