import Foundation
import Darwin
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

final class FakeBrightnessClient: NSObject {
    typealias DisplayBlock = @convention(block) (NSString, UInt64, AnyObject?) -> Void
    typealias KeyboardBlock = @convention(block) (NSString, AnyObject?, UInt64) -> Void
    var displayBlock: DisplayBlock?
    var keyboardBlock: KeyboardBlock?
    @objc(registerDisplayNotificationCallbackBlock:)
    func registerDisplay(_ block: @escaping DisplayBlock) { displayBlock = block }
    @objc(registerKeyboardNotificationCallbackBlock:)
    func registerKeyboard(_ block: @escaping KeyboardBlock) { keyboardBlock = block }
    @objc(registerNotificationForKeys:andDisplay:)
    func registerDisplayKeys(_ keys: NSArray, id: UInt64) {}
    @objc(registerNotificationForKeys:keyboardID:)
    func registerKeyboardKeys(_ keys: NSArray, id: UInt64) {}
    @objc(unregisterNotificationForKeys:andDisplay:)
    func unregisterDisplayKeys(_ keys: NSArray, id: UInt64) {}
    @objc(unregisterNotificationForKeys:keyboardID:)
    func unregisterKeyboardKeys(_ keys: NSArray, id: UInt64) {}
    @objc func unregisterDisplayNotificationBlock() { displayBlock = nil }
    @objc func unregisterKeyboardNotificationBlock() { keyboardBlock = nil }
}
func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
let fake = FakeBrightnessClient()
let events = BrightnessEvents(client: fake)
var received: [(Double, Bool)] = []
var keyboard: [Double] = []
events.start(display: 17, keyboard: 2,
    displayChanged: { received.append(($0, $1)) },
    keyboardSliderChanged: { keyboard.append($0) })
for reason in ["User Slider", "Auto-brightness", "User change", "ALS Update", "Future unknown reason"] {
    fake.displayBlock?("CBDisplayBrightnessState", 17,
        ["DisplayServicesBrightness": NSNumber(value: 0.5), "CBReasonForBrightnessChange": reason] as NSDictionary)
}
fake.keyboardBlock?("KeyboardBacklightBrightnessSlider", NSNumber(value: 0.7), 2)
fake.keyboardBlock?("KeyboardBacklightBrightnessSlider", NSNumber(value: 0.9), 99)
fake.keyboardBlock?("KeyboardBacklightBrightnessSlider", NSNumber(value: Double.nan), 2)
drain()
precondition(received.count == 5)
precondition(received.map { $0.1 } == [false, true, false, true, true])
for level in [0.2, 0.4, 0.8] {
    fake.displayBlock?("DisplayServicesUserBrightness", 17, NSNumber(value: level))
    drain()
    precondition(received.last!.0 == level && !received.last!.1, "Slider update requires no final state event")
}
precondition(keyboard == [0.7], "Manual keyboard slider event lost or incorrect ABI")
let staleDisplay = fake.displayBlock
let staleKeyboard = fake.keyboardBlock
events.stop()
staleDisplay?("CBDisplayBrightnessState", 17,
    ["DisplayServicesBrightness": NSNumber(value: 0.8), "CBReasonForBrightnessChange": "User Slider"] as NSDictionary)
staleKeyboard?("KeyboardBacklightBrightnessSlider", NSNumber(value: 0.8), 2)
drain()
precondition(received.count == 8 && keyboard.count == 1, "Callback after stop")
let policy = BrightnessChangePolicy.self
precondition(!policy.showKeyboardChange(manualChanged: false, hasManualValue: true, automaticEnabled: true, idleDimmed: false, explicitSlider: false))
precondition(policy.showKeyboardChange(manualChanged: true, hasManualValue: true, automaticEnabled: true, idleDimmed: true, explicitSlider: false))
precondition(policy.showKeyboardChange(manualChanged: false, hasManualValue: true, automaticEnabled: true, idleDimmed: false, explicitSlider: true))
precondition(!policy.showKeyboardChange(manualChanged: false, hasManualValue: false, automaticEnabled: true, idleDimmed: false, explicitSlider: false))
precondition(!policy.manualValueChanged(0.5, 0.5))
precondition(policy.manualValueChanged(0.5, 0.7))
precondition(!policy.manualValueChanged(nil, 0.7))
precondition(policy.isAutomaticDisplayReason(nil), "Unclassified state changes must stay silent")
precondition(policy.isAutomaticDisplayReason("Ambient ALS Update"), "Ambient changes must stay silent")
print("PASS: live display slider origins, automatic ambient filtering, manual keyboard slider ABI, invalid values and stale callbacks")
