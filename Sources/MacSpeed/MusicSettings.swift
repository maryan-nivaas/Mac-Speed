import Foundation

/// User preferences for the Music Controls module, persisted in UserDefaults.
final class MusicSettings: ObservableObject {
    static let shared = MusicSettings()

    /// Intervals offered for the skip back / forward buttons.
    static let skipIntervals = [5, 10, 15, 20, 30, 40]

    private let skipKey = "music.skipSeconds"

    /// Seconds one tap of the skip buttons moves. Rapid repeat taps add another step each.
    @Published var skipSeconds: Int {
        didSet { UserDefaults.standard.set(skipSeconds, forKey: skipKey) }
    }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: skipKey)
        skipSeconds = Self.skipIntervals.contains(saved) ? saved : 10
    }
}
