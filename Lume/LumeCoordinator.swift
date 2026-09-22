import AppKit
import Combine

@MainActor
final class LumeCoordinator: ObservableObject {
    let capsule = CapsuleController()
    let hud = HUDManager.shared
    let corners = OverlayManager()
    let player = MediaRemoteWrapper.shared
    @Published var capsuleEnabled: Bool {
        didSet { capsule.isEnabled = capsuleEnabled }
    }
    @Published var hudEnabled = (UserDefaults.standard.object(forKey: "LumeHUDEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(hudEnabled, forKey: "LumeHUDEnabled")
            updateHUD()
        }
    }
    init() { capsuleEnabled = capsule.isEnabled }
    func start() {
        _ = AudioDeviceManager.shared
        MediaKeyManager.shared.onVolumeChange = { [weak self] value in
            guard self?.hudEnabled == true else { return }
            self?.hud.showVolume(value)
        }
        MediaKeyManager.shared.onDisplayBrightnessChange = { [weak self] value in
            guard self?.hudEnabled == true else { return }
            self?.hud.showDisplayBrightness(value)
        }
        MediaKeyManager.shared.onKeyboardBrightnessChange = { [weak self] value in
            guard self?.hudEnabled == true else { return }
            self?.hud.showKeyboardBrightness(value)
        }
        capsule.start()
        corners.start()
        player.start()
        updateHUD()
    }
    func updateHUD() {
        if hudEnabled { MediaKeyManager.shared.checkAccessibility(prompt: false) }
        else {
            NativeHUDController.shared.stop()
            MediaKeyManager.shared.stop()
            hud.stop()
        }
    }
    func stop() {
        capsule.stop()
        player.stop()
        NativeHUDController.shared.stop()
        MediaKeyManager.shared.stop()
        corners.stop()
        hud.stop()
    }
    static func migratePreferences() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "LumeMigrationDone") else { return }
        let sources: [(String, [String])] = [
            ("com.eduvini.statuscapsule", ["StatusCapsuleEnabled", "ElementOrderV4", "ElementOrder", "StatusOrder", "ShowsPercentage", "ShowsPercentageWhileCharging"]),
            ("com.example.app", ["HUDStyle", "CornerRadius", "IsEffectEnabled", "freeClipDeviceUID"])
        ]
        for (domain, keys) in sources {
            let values = defaults.persistentDomain(forName: domain) ?? [:]
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = values[key] { defaults.set(value, forKey: key) }
            }
        }
        defaults.set(true, forKey: "LumeMigrationDone")
    }
}
