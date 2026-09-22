import AppKit
import SwiftUI
import Darwin

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var coordinator: LumeCoordinator!
    private var activationObserver: NSObjectProtocol?
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A watchdog exiting between heartbeats must produce a handled write
        // error, never terminate the host application with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        LumeCoordinator.migratePreferences()
        coordinator = LumeCoordinator()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Eko")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Configurações do Eko…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair do Eko", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        coordinator.start()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.coordinator.updateHUD() }
        }
        if !UserDefaults.standard.bool(forKey: "LumeWelcomeShown") {
            openSettings()
            UserDefaults.standard.set(true, forKey: "LumeWelcomeShown")
        }
    }
    @objc private func openSettings() {
        if window == nil {
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            settings.title = "Eko"
            settings.titlebarAppearsTransparent = true
            settings.isReleasedWhenClosed = false
            settings.contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator, model: coordinator.capsule.model, hud: coordinator.hud, corners: coordinator.corners, player: coordinator.player))
            settings.center()
            window = settings
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        coordinator?.stop()
    }
}
