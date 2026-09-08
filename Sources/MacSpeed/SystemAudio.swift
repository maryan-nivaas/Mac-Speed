import Foundation

/// Toggles the system-wide output mute, independent of which app is playing audio.
enum SystemAudio {
    static func toggleMute() {
        run("set volume output muted (not (output muted of (get volume settings)))")
    }

    private static func run(_ appleScript: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]
        task.standardOutput = nil
        task.standardError = nil
        try? task.run()
    }
}
