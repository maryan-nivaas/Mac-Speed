import AppKit

enum Player: String {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
}

private struct PlayerState {
    var player: Player
    var isPlaying: Bool
    var trackName: String
    var artist: String
    var artworkKey: String
    var artworkURL: String?
}

/// Fallback bridge: talks to the Spotify / Apple Music desktop apps via osascript.
/// Used only when the `media-control` CLI is not installed.
final class PlayerBridge: MusicBridge {
    private let queue = DispatchQueue(label: "macspeed.bridge")
    private let separator = "|~|"
    private var artworkCache: (key: String, image: NSImage)?
    private var lastPlayer: Player?

    private var musicArtworkPath: String {
        NSTemporaryDirectory() + "macspeed_artwork"
    }

    private func runningPlayers() -> [Player] {
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return [Player.spotify, .music].filter { ids.contains($0.rawValue) }
    }

    private func osascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stateScript(for player: Player) -> String {
        let artworkField = player == .spotify ? "artwork url of t" : "\"\""
        return """
        tell application id "\(player.rawValue)"
            set st to player state as text
            try
                set t to current track
                return st & "\(separator)" & name of t & "\(separator)" & artist of t & "\(separator)" & \(artworkField)
            on error
                return st
            end try
        end tell
        """
    }

    private func fetchState(for player: Player) -> PlayerState? {
        guard let output = osascript(stateScript(for: player)) else { return nil }
        let parts = output.components(separatedBy: separator)
        guard parts.count >= 3 else { return nil }
        let name = parts[1]
        let artist = parts[2]
        return PlayerState(
            player: player,
            isPlaying: parts[0] == "playing",
            trackName: name,
            artist: artist,
            artworkKey: "\(player.rawValue)::\(name)::\(artist)",
            artworkURL: parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil
        )
    }

    /// Prefers whichever player is actively playing; Spotify wins ties.
    func poll(_ completion: @escaping (BarState?, NSImage?) -> Void) {
        queue.async {
            let states = self.runningPlayers().compactMap(self.fetchState(for:))
            let state = states.first(where: \.isPlaying) ?? states.first
            self.lastPlayer = state?.player
            let artwork = state.flatMap(self.artwork(for:))
            let barState = state.map {
                BarState(isPlaying: $0.isPlaying, trackName: $0.trackName, sourceBundleID: $0.player.rawValue)
            }
            DispatchQueue.main.async { completion(barState, artwork) }
        }
    }

    private func artwork(for state: PlayerState) -> NSImage? {
        if let cached = artworkCache, cached.key == state.artworkKey {
            return cached.image
        }
        var image: NSImage?
        if state.player == .spotify, let urlString = state.artworkURL,
           let url = URL(string: urlString), let data = try? Data(contentsOf: url) {
            image = NSImage(data: data)
        } else if state.player == .music {
            image = fetchMusicArtwork()
        }
        if let image { artworkCache = (state.artworkKey, image) }
        return image
    }

    private func fetchMusicArtwork() -> NSImage? {
        let script = """
        tell application id "com.apple.Music"
            set aw to data of artwork 1 of current track
        end tell
        set f to open for access POSIX file "\(musicArtworkPath)" with write permission
        set eof f to 0
        write aw to f
        close access f
        return "ok"
        """
        guard osascript(script) == "ok" else { return nil }
        return NSImage(contentsOfFile: musicArtworkPath)
    }

    private func command(_ verb: String) {
        queue.async {
            guard let player = self.lastPlayer else { return }
            _ = self.osascript("tell application id \"\(player.rawValue)\" to \(verb)")
        }
    }

    func playPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    // Relative and run serially on `queue`, so rapid taps stack on their own.
    func seek(by seconds: Double) {
        command("set player position to (player position + (\(seconds)))")
    }
}
