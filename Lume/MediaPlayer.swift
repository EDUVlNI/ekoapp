import AppKit
import Combine

enum MusicSourcePolicy {
    static let allowed: [String: String] = [
        "com.spotify.client": "Spotify",
        "com.deezer.deezer-desktop": "Deezer",
        "com.apple.Music": "Apple Music"
    ]
    static func allows(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return allowed[bundleID] != nil
    }
}

struct MediaSourceAPI {
    var pid: ((DispatchQueue, @escaping (Int32) -> Void) -> Void)?
    var info: ((DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void)?
    var playing: ((DispatchQueue, @escaping (Bool) -> Void) -> Void)?
    var command: ((UInt32, CFDictionary?) -> Bool)?
    var bundle: (Int32) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
}

final class MediaRemoteWrapper: ObservableObject {
    static let shared = MediaRemoteWrapper()
    struct Track {
        var title = ""
        var artist = ""
        var album = ""
        var playing = false
        var artwork: NSImage?
        var source = ""
        var pid: Int32 = 0
    }
    @Published private(set) var track = Track()
    @Published private(set) var status = "Aguardando Spotify, Deezer ou Apple Music"
    @Published var floatingPlayerEnabled = (UserDefaults.standard.object(forKey: "FloatingPlayerEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(floatingPlayerEnabled, forKey: "FloatingPlayerEnabled")
            if !floatingPlayerEnabled { HUDManager.shared.hideNowPlaying() }
        }
    }
    @Published var enabled = (UserDefaults.standard.object(forKey: "PlayerEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "PlayerEnabled")
            if enabled { refreshAll() } else { generation &+= 1; clear() }
        }
    }
    var songTitle: String { track.title }
    var artistName: String { track.artist }
    var albumName: String { track.album }
    var isPlaying: Bool { track.playing }
    var albumArtwork: NSImage? { track.artwork }

    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias PlayingFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias CommandFunction = @convention(c) (UInt32, CFDictionary?) -> Bool
    private var getPID: ((DispatchQueue, @escaping (Int32) -> Void) -> Void)?
    private var getInfo: ((DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void)?
    private var getPlaying: ((DispatchQueue, @escaping (Bool) -> Void) -> Void)?
    private var sendCommand: ((UInt32, CFDictionary?) -> Bool)?
    private var resolveBundle: (Int32) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    private var register: (@convention(c) (DispatchQueue) -> Void)?
    private var unregister: (@convention(c) () -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var artworkData: Data?
    private var handle: UnsafeMutableRawPointer?

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        guard let handle else { return }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") { let function = unsafeBitCast(symbol, to: PIDFunction.self); getPID = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") { let function = unsafeBitCast(symbol, to: InfoFunction.self); getInfo = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") { let function = unsafeBitCast(symbol, to: PlayingFunction.self); getPlaying = { queue, done in function(queue) { done($0) } } }
        if let symbol = dlsym(handle, "MRMediaRemoteSendCommand") { let function = unsafeBitCast(symbol, to: CommandFunction.self); sendCommand = { function($0, $1) } }
        if let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") { register = unsafeBitCast(symbol, to: (@convention(c) (DispatchQueue) -> Void).self) }
        if let symbol = dlsym(handle, "MRMediaRemoteUnregisterForNowPlayingNotifications") { unregister = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self) }
    }

    init(api: MediaSourceAPI) {
        getPID = api.pid
        getInfo = api.info
        getPlaying = api.playing
        sendCommand = api.command
        resolveBundle = api.bundle
    }

    func start() {
        guard timer == nil else { return }
        register?(.main)
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.refreshAll() })
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshAll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshAll()
    }

    func stop() {
        generation &+= 1
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        unregister?()
        clear()
    }

    func refreshAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        let request = generation
        guard enabled else { clear(); return }
        guard let getPID, let getInfo, let getPlaying else {
            clear(); status = "Player indisponível nesta versão do macOS"; return
        }
        getPID(.main) { [weak self] pid in
            guard let self, self.generation == request, self.enabled else { return }
            guard let bundle = self.resolveBundle(pid),
                  MusicSourcePolicy.allows(bundle) else { self.clear(); return }
            getInfo(.main) { [weak self] dictionary in
                guard let self, self.generation == request, self.enabled else { return }
                let info = dictionary as? [String: Any] ?? [:]
                getPlaying(.main) { [weak self] playing in
                    guard let self, self.generation == request, self.enabled else { return }
                    // Metadata and playback callbacks can outlive a source change.
                    getPID(.main) { [weak self] verifiedPID in
                        guard let self, self.generation == request, self.enabled else { return }
                        guard verifiedPID == pid,
                              self.resolveBundle(verifiedPID) == bundle else { self.clear(); return }
                        self.apply(info: info, playing: playing, pid: pid, bundle: bundle)
                    }
                }
            }
        }
    }

    private func apply(info: [String: Any], playing: Bool, pid: Int32, bundle: String) {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.isEmpty else { clear(); return }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let newData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let identityChanged = track.pid != pid || track.title != title || track.artist != artist || track.album != album
        let shouldPresent = identityChanged || track.playing != playing
        let image = !identityChanged && newData == artworkData ? track.artwork : newData.flatMap(NSImage.init(data:))
        if shouldPresent || newData != artworkData {
            track = Track(title: title, artist: artist, album: album, playing: playing, artwork: image, source: MusicSourcePolicy.allowed[bundle] ?? "", pid: pid)
            artworkData = newData
        }
        status = "\(track.source) · \(playing ? "Reproduzindo" : "Pausado")"
        if shouldPresent && floatingPlayerEnabled { HUDManager.shared.showNowPlaying() }
    }

    private func clear() {
        if track.pid != 0 || !track.title.isEmpty { track = Track(); artworkData = nil }
        HUDManager.shared.hideNowPlaying()
        status = enabled ? "Aguardando Spotify, Deezer ou Apple Music" : "Player desativado"
    }

    private func command(_ command: UInt32) {
        let expected = track.pid
        guard enabled, expected > 0 else { return }
        getPID?(.main) { [weak self] pid in
            guard let self, self.enabled, pid == expected, self.track.pid == expected,
                  MusicSourcePolicy.allows(self.resolveBundle(pid)) else { return }
            _ = self.sendCommand?(command, nil)
        }
    }
    func togglePlayPause() { command(2) }
    func nextTrack() { command(4) }
    func previousTrack() { command(5) }
}
