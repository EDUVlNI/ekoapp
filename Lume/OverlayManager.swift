import AppKit
import SwiftUI
import Combine

class OverlayManager: ObservableObject {
    @Published var radius: CGFloat {
        didSet {
            UserDefaults.standard.set(radius, forKey: "CornerRadius")
            updateOverlays()
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "IsEffectEnabled")
            updateOverlays()
        }
    }

    private var windows: [NSWindow] = []

    init() {
        let savedRadius = UserDefaults.standard.object(forKey: "CornerRadius")
        self.radius = savedRadius == nil ? 20.0 : CGFloat(UserDefaults.standard.double(forKey: "CornerRadius"))

        let savedEnabled = UserDefaults.standard.object(forKey: "IsEffectEnabled")
        self.isEnabled = savedEnabled == nil ? true : UserDefaults.standard.bool(forKey: "IsEffectEnabled")
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuildWindows()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        destroyWindows()
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    private func destroyWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func rebuildWindows() {
        destroyWindows()
        guard isEnabled else { return }

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = CornersView(radius: radius)
            let hostingView = NSHostingView(rootView: view)
            window.contentView = hostingView
            windows.append(window)
        }
    }

    private func updateOverlays() {
        if !isEnabled {
            destroyWindows()
            return
        }

        if windows.isEmpty || windows.count != NSScreen.screens.count {
            rebuildWindows()
            return
        }

        for window in windows {
            if let hostingView = window.contentView as? NSHostingView<CornersView> {
                hostingView.rootView = CornersView(radius: radius)
            }
        }
    }
}

class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.hasShadow = false
        self.orderFront(nil)
    }
}

struct CornersView: View {
    var radius: CGFloat

    var body: some View {
        Color.black
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .blendMode(.destinationOut)
                    )
            )
            .compositingGroup()
            .edgesIgnoringSafeArea(.all)
    }
}
