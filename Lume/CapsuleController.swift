import AppKit
import SwiftUI

@MainActor
final class CapsuleController: NSObject {
    private enum Constants {
        static let enabledKey = "StatusCapsuleEnabled"
        static let topMargin: CGFloat = 2
        static let trailingMargin: CGFloat = 12
        static let hoverMargin: CGFloat = 4
    }

    let model = StatusModel()
    private var panel: NSPanel?
    private var monitorTimer: Timer?
    private var hideGeneration: UInt64 = 0
    private var lastShouldShow: Bool?
    private var menuHiddenUntil: TimeInterval = 0
    private var lastMenuScan: TimeInterval = 0
    private var systemMenuWindowVisible = false

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Constants.enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Constants.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.enabledKey)
            refreshPresentation()
        }
    }

    func start() {
        guard panel == nil else { return }
        let view = CapsuleView(model: model)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 68)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.alphaValue = 0
        self.panel = panel

        model.start()
        positionPanel()
        refreshPresentation()

        let timer = Timer(timeInterval: 0.04, target: self, selector: #selector(monitorTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWoke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        model.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panel?.orderOut(nil)
        panel = nil
        lastShouldShow = nil
    }

    @objc private func screenConfigurationChanged() {
        positionPanel()
        refreshPresentation()
    }

    @objc private func workspaceWoke() {
        positionPanel()
        refreshPresentation()
    }

    @objc private func monitorTimerFired() {
        refreshPresentation()
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func positionPanel() {
        guard let panel, let screen = preferredScreen() else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = NSSize(width: 560, height: 68)
        panel.setContentSize(size)
        let origin = NSPoint(
            x: screen.frame.maxX - size.width - Constants.trailingMargin,
            y: screen.frame.maxY - size.height - Constants.topMargin
        )
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func refreshPresentation() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let hoverArea = screenRect(for: model.contentHitView)
            .insetBy(dx: -Constants.hoverMargin, dy: -Constants.hoverMargin)
        let pointerIsOverCapsule = hoverArea.contains(mouse)
        let siriRect = screenRect(for: model.siriHitView)
        let pointerIsOverSiri = model.elements.contains(.siri) && !siriRect.isEmpty && siriRect.contains(mouse)
        panel.ignoresMouseEvents = !pointerIsOverSiri
        let nativeMenuBarIsVisible = menuBarIsVisible(mouse: mouse)
        let shouldShow = isEnabled && !nativeMenuBarIsVisible && (!pointerIsOverCapsule || pointerIsOverSiri)

        // The system menu takes precedence, including during an ongoing hover fade.
        if nativeMenuBarIsVisible {
            lastShouldShow = false
            model.isPresented = false
            panel.ignoresMouseEvents = true
            if panel.isVisible {
                hideGeneration &+= 1
                panel.orderOut(nil)
            }
            return
        }

        guard lastShouldShow != shouldShow else { return }
        lastShouldShow = shouldShow
        model.isPresented = shouldShow

        if shouldShow {
            show(panel)
        } else {
            hide(panel)
        }
    }

    private func show(_ panel: NSPanel) {
        hideGeneration &+= 1
        panel.alphaValue = 1
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func menuBarIsVisible(mouse: CGPoint) -> Bool {
        guard let screen = preferredScreen() else { return NSMenu.menuBarVisible() }
        let now = ProcessInfo.processInfo.systemUptime
        // Hide before the auto-hidden menu starts sliding into the display.
        let atTop = mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
            && mouse.y >= screen.frame.maxY - 2 && mouse.y <= screen.frame.maxY
        if now - lastMenuScan >= 0.1 {
            lastMenuScan = now
            systemMenuWindowVisible = hasVisibleMenuWindow(on: screen)
        }
        if atTop || systemMenuWindowVisible || NSMenu.menuBarVisible() {
            menuHiddenUntil = now + 0.18
            return true
        }
        return now < menuHiddenUntil
    }

    private func hasVisibleMenuWindow(on screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let display = CGDisplayBounds(number.uint32Value)
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return windows.contains { window in
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == menuLevel,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.01,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            return Self.isMenuBarBounds(bounds, display: display)
        }
    }

    static func isMenuBarBounds(_ bounds: CGRect, display: CGRect) -> Bool {
        let overlap = bounds.intersection(display)
        return !overlap.isNull && overlap.width >= display.width * 0.9
            && bounds.height >= 10 && bounds.height <= 80
            && bounds.minY <= display.minY + 2 && bounds.maxY > display.minY + 2
    }

    private func screenRect(for view: NSView?) -> CGRect {
        guard let view, let window = view.window else { return .null }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    private func hide(_ panel: NSPanel) {
        guard panel.isVisible else { return }
        hideGeneration &+= 1
        let generation = hideGeneration
        // Let SwiftUI finish the blur before removing the window. A pointer exit
        // invalidates this generation so an old hide cannot dismiss a new show.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self, weak panel] in
            guard let self, let panel, self.hideGeneration == generation else { return }
            panel.orderOut(nil)
        }
    }
}
