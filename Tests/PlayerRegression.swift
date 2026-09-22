import AppKit

// A presentation spy allows the real player logic to be tested without a GUI.
final class HUDManager {
    static let shared = HUDManager()
    var presentations = 0
    func showNowPlaying() { presentations += 1 }
    func hideNowPlaying() {}
}

@main
struct PlayerRegression {
    static func main() {
        for app in ["com.spotify.client", "com.deezer.deezer-desktop", "com.apple.Music"] {
            precondition(MusicSourcePolicy.allows(app))
        }
        for app in [nil, "com.apple.Safari", "com.google.Chrome", "us.zoom.xos", "com.spotify.client.fake"] as [String?] {
            precondition(!MusicSourcePolicy.allows(app))
        }
        var pid: Int32 = 1
        var hold = false
        var pending: [(CFDictionary?) -> Void] = []
        var commands: [UInt32] = []
        var reads = 0
        let info = ["kMRMediaRemoteNowPlayingInfoTitle": "Test song", "kMRMediaRemoteNowPlayingInfoArtist": "Test artist", "kMRMediaRemoteNowPlayingInfoAlbum": "Test album"] as CFDictionary
        let api = MediaSourceAPI(
            pid: { _, done in done(pid) },
            info: { _, done in reads += 1; if hold { pending.append(done) } else { done(info) } },
            playing: { _, done in done(true) },
            command: { value, _ in commands.append(value); return true },
            bundle: { [1: "com.spotify.client", 2: "com.apple.Safari", 3: "com.deezer.deezer-desktop", 4: "com.apple.Music"][$0] }
        )
        let player = MediaRemoteWrapper(api: api)
        let enabled = player.enabled
        let floating = player.floatingPlayerEnabled
        defer { player.enabled = enabled; player.floatingPlayerEnabled = floating }
        player.floatingPlayerEnabled = false
        let before = HUDManager.shared.presentations
        player.enabled = true
        precondition(player.songTitle == "Test song")
        precondition(HUDManager.shared.presentations == before, "Capsule-only mode must not show the floating player")
        player.floatingPlayerEnabled = true
        precondition(player.albumName == "Test album")
        player.togglePlayPause()
        precondition(commands == [2])
        pid = 2
        player.nextTrack()
        precondition(commands == [2], "Never control a browser after source changes")
        let oldReads = reads
        player.refreshAll()
        precondition(reads == oldReads && player.songTitle.isEmpty)
        pid = 1; hold = true
        player.refreshAll()
        pid = 2
        pending.removeFirst()(info)
        precondition(player.songTitle.isEmpty, "Discard a source switch during metadata fetch")
        pid = 1; player.refreshAll()
        pid = 3; player.refreshAll()
        pending.removeFirst()(info)
        precondition(player.songTitle.isEmpty, "Discard an older request")
        pending.removeFirst()(info)
        precondition(player.track.source == "Deezer")
        pid = 4; player.refreshAll()
        player.enabled = false
        pending.removeFirst()(info)
        precondition(player.songTitle.isEmpty, "Disabling cancels queued metadata")
        hold = false; player.enabled = true
        precondition(player.track.source == "Apple Music")
        print("PASS source allowlist, browser exclusion, source-change races, stale responses, disable and guarded controls")
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            for symbol in ["MRMediaRemoteGetNowPlayingApplicationPID", "MRMediaRemoteGetNowPlayingInfo", "MRMediaRemoteGetNowPlayingApplicationIsPlaying", "MRMediaRemoteSendCommand"] {
                precondition(dlsym(handle, symbol) != nil, symbol)
            }
            print("PASS required MediaRemote symbols available on this Mac")
        } else { fatalError("MediaRemote unavailable") }
    }
}
