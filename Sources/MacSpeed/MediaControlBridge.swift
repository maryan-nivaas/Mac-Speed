import AppKit

struct BarState {
    var isPlaying: Bool
    var trackName: String
    var sourceBundleID: String?
}

protocol MusicBridge: AnyObject {
    func poll(_ completion: @escaping (BarState?, NSImage?) -> Void)
    func playPause()
    func nextTrack()
    func previousTrack()
    /// Moves the playhead by `seconds` (negative = back). Calls arriving in quick
    /// succession stack, so two taps of +10 land 20s ahead.
    func seek(by seconds: Double)
}

/// System-wide now-playing via the `media-control` CLI (ungive/media-control),
/// which reads macOS's own Now Playing state — so browser tabs, Spotify, Music,
/// anything the system sees. Works on macOS 15.4+ where MediaRemote is locked down.
final class MediaControlBridge: MusicBridge {
    private let queue = DispatchQueue(label: "macspeed.mediacontrol")
    private let binaryPath: String
    private var artworkCache: (key: String, image: NSImage)?
    /// Where the last seek landed. Rapid follow-up taps build on this instead of
    /// re-reading the player, which may not have reported the new position yet.
    private var lastSeek: (target: Double, at: Date)?
    private let seekStackWindow: TimeInterval = 1.5

    static func ifAvailable() -> MediaControlBridge? {
        let candidates = ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }
        return MediaControlBridge(binaryPath: path)
    }

    private init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    private func run(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        // Read before waiting so a large artwork payload can't deadlock the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    func poll(_ completion: @escaping (BarState?, NSImage?) -> Void) {
        queue.async {
            var state: BarState?
            var artwork: NSImage?
            if let data = self.run(["get"]),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["bundleIdentifier"] != nil {
                let rawTitle = json["title"] as? String ?? ""
                let title = rawTitle.isEmpty ? "Now Playing" : rawTitle
                state = BarState(
                    isPlaying: json["playing"] as? Bool ?? false,
                    trackName: title,
                    sourceBundleID: json["bundleIdentifier"] as? String
                )
                let key = "\(title)::\(json["artist"] as? String ?? "")"
                if let cached = self.artworkCache, cached.key == key {
                    artwork = cached.image
                } else if let base64 = json["artworkData"] as? String,
                          let bytes = Data(base64Encoded: base64),
                          let image = NSImage(data: bytes) {
                    self.artworkCache = (key, image)
                    artwork = image
                }
            }
            DispatchQueue.main.async { completion(state, artwork) }
        }
    }

    private func command(_ name: String) {
        queue.async { _ = self.run([name]) }
    }

    func playPause() { command("toggle-play-pause") }
    func nextTrack() { command("next-track") }
    func previousTrack() { command("previous-track") }

    func seek(by seconds: Double) {
        queue.async {
            guard let data = self.run(["get", "--now"]),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let elapsed = json["elapsedTime"] as? Double
            else { return }
            let base: Double
            if let last = self.lastSeek, Date().timeIntervalSince(last.at) < self.seekStackWindow {
                base = last.target
            } else {
                base = elapsed
            }
            var target = max(0, base + seconds)
            if let duration = json["duration"] as? Double, duration > 0 {
                target = min(target, max(0, duration - 1))
            }
            _ = self.run(["seek", String(format: "%.3f", target)])
            self.lastSeek = (target, Date())
        }
    }
}
