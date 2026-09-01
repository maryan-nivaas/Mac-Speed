import AppKit

/// The 200px now-playing strip: artwork, marquee title, play/pause, prev, next.
final class MusicModule: BarModule {
    let id = "music"
    let title = "Music Controls"
    let moduleDescription = "Now playing with album art and track name, plus one-click play/pause, previous and next. Works with browsers, Spotify and Apple Music."
    let symbolName = "music.note"

    private weak var manager: AppDelegate?
    private var statusItem: NSStatusItem?
    private var barView: PlayerBarView?
    // System-wide Now Playing when media-control is installed; AppleScript fallback otherwise.
    private let bridge: MusicBridge = MediaControlBridge.ifAvailable() ?? PlayerBridge()
    private var pollTimer: Timer?
    private var currentState: BarState?

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

        barView.onPlayPause = { [weak self] in
            guard let self, let state = self.currentState else { return }
            // Flip the icon immediately; the next poll confirms the real state.
            self.barView?.setPlaying(!state.isPlaying)
            self.bridge.playPause()
            self.pollSoon()
        }
        barView.onPrevious = { [weak self] in
            self?.bridge.previousTrack()
            self?.pollSoon()
        }
        barView.onNext = { [weak self] in
            self?.bridge.nextTrack()
            self?.pollSoon()
        }
        barView.onOpenPlayer = { [weak self] in
            guard let self, let bundleID = self.currentState?.sourceBundleID else { return }
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleID }?
                .activate()
        }
        barView.contextMenuProvider = { [weak self] in self?.manager?.sharedMenu() }

        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        barView = nil
        currentState = nil
    }

    func menusChanged() {}   // menu is built fresh on each right-click

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
