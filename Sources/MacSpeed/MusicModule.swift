import AppKit
import Combine

/// The 252px now-playing strip: artwork, marquee title, skip back, play/pause,
/// skip forward, prev, next.
final class MusicModule: BarModule {
    let id = "music"
    let title = "Music Controls"
    let moduleDescription = "Now playing with album art and track name, plus play/pause, skip back/forward (tap again to jump further), previous and next. Works with browsers, Spotify and Apple Music."
    let symbolName = "music.note"

    private weak var manager: AppDelegate?
    private var statusItem: NSStatusItem?
    private var barView: PlayerBarView?
    // System-wide Now Playing when media-control is installed; AppleScript fallback otherwise.
    private let bridge: MusicBridge = MediaControlBridge.ifAvailable() ?? PlayerBridge()
    private var pollTimer: Timer?
    private var currentState: BarState?
    private var settingsObserver: AnyCancellable?
    /// Running total shown as feedback while taps keep stacking ("+10s", "+20s", …).
    private var skipStreak: (total: Int, at: Date)?

    func start(manager: AppDelegate) {
        self.manager = manager
        let barView = PlayerBarView(
            frame: NSRect(x: 0, y: 0, width: PlayerBarView.totalWidth,
                          height: NSStatusBar.system.thickness)
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: PlayerBarView.totalWidth)
        statusItem.button?.addSubview(barView)
        self.barView = barView
        self.statusItem = statusItem

        barView.onPlayPause = { [weak self] in self?.togglePlayPause() }
        barView.onPrevious = { [weak self] in self?.previousTrack() }
        barView.onNext = { [weak self] in self?.nextTrack() }
        barView.onSkipBackward = { [weak self] in self?.skipBackward() }
        barView.onSkipForward = { [weak self] in self?.skipForward() }
        settingsObserver = MusicSettings.shared.$skipSeconds.sink { [weak barView] seconds in
            barView?.setSkipInterval(seconds)
        }
        barView.onOpenPlayer = { [weak self] in
            guard let self, let bundleID = self.currentState?.sourceBundleID else { return }
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleID }?
                .activate()
        }
        barView.contextMenuProvider = { [weak self] in self?.contextMenu() }

        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        settingsObserver = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        barView = nil
        currentState = nil
    }

    func menusChanged() {}   // menu is built fresh on each right-click

    // MARK: - Actions (also used by the global media hotkey)

    /// Toggles playback regardless of current state.
    func togglePlayPause() {
        // Flip the icon immediately; the next poll confirms the real state.
        if let state = currentState { barView?.setPlaying(!state.isPlaying) }
        bridge.playPause()
        pollSoon()
    }

    /// Starts playback only if currently paused (no-op if already playing or state unknown).
    func play() {
        guard let state = currentState, !state.isPlaying else { return }
        togglePlayPause()
    }

    /// Pauses playback only if currently playing (no-op if already paused or state unknown).
    func pause() {
        guard let state = currentState, state.isPlaying else { return }
        togglePlayPause()
    }

    func nextTrack() {
        bridge.nextTrack()
        pollSoon()
    }

    func previousTrack() {
        bridge.previousTrack()
        pollSoon()
    }

    func skipForward() { skip(direction: 1) }
    func skipBackward() { skip(direction: -1) }

    /// Each tap seeks right away; taps within the stack window add another step,
    /// so with a 10s interval a double tap lands 20s away, a triple tap 30s.
    private func skip(direction: Int) {
        guard currentState != nil else { return }
        let step = MusicSettings.shared.skipSeconds * direction
        bridge.seek(by: Double(step))
        var total = step
        if let streak = skipStreak, Date().timeIntervalSince(streak.at) < 1.5,
           streak.total.signum() == direction {
            total += streak.total
        }
        skipStreak = (total, Date())
        barView?.showSkipFeedback(total > 0 ? "+\(total)s" : "−\(-total)s")
    }

    // MARK: - Right-click menu

    private func contextMenu() -> NSMenu? {
        guard let menu = manager?.sharedMenu() else { return nil }
        let intervals = NSMenu()
        for seconds in MusicSettings.skipIntervals {
            let item = NSMenuItem(title: "\(seconds) seconds",
                                  action: #selector(chooseSkipInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = seconds == MusicSettings.shared.skipSeconds ? .on : .off
            intervals.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Skip Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.insertItem(intervalItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func chooseSkipInterval(_ sender: NSMenuItem) {
        MusicSettings.shared.skipSeconds = sender.tag
    }

    private func poll() {
        bridge.poll { [weak self] state, artwork in
            guard let self else { return }
            self.currentState = state
            if let state {
                self.barView?.update(isPlaying: state.isPlaying,
                                     trackName: state.trackName, artwork: artwork)
            } else {
                self.barView?.showIdle()
            }
        }
    }

    private func pollSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.poll() }
    }
}
