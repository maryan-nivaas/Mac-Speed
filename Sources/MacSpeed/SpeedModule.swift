import AppKit

/// Live network speed in the menu bar (ported from Mac-Speed), with display
/// mode, update interval, and an on-demand speed test in its dropdown menu.
final class SpeedModule: NSObject, BarModule {
    let id = "speed"
    let title = "Network Speed"
    let moduleDescription = "Live download and upload speed in the menu bar, with display options, update interval and an on-demand speed test."
    let symbolName = "speedometer"

    private weak var manager: AppDelegate?
    private var statusItem: NSStatusItem?
    private let monitor = NetworkMonitor()
    private var timer: Timer?
    private var speedTestWC: SpeedTestWindowController?

    private let intervals: [Double] = [1, 2, 5, 10, 30]
    private let intervalKey = "updateInterval"
    private let displayModeKey = "displayMode"   // "down" | "up" | "both"

    // Remember the last rate so we can redraw instantly when the display
    // mode changes, without waiting for the next timer tick.
    private var lastDown: Double = 0
    private var lastUp: Double = 0

    private var interval: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: intervalKey)
            return intervals.contains(stored) ? stored : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: intervalKey) }
    }

    private var displayMode: String {
        get { UserDefaults.standard.string(forKey: displayModeKey) ?? "both" }
        set { UserDefaults.standard.set(newValue, forKey: displayModeKey) }
    }

    func start(manager: AppDelegate) {
        self.manager = manager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(down: 0, up: 0)
        buildMenu()
        monitor.reset()
        _ = monitor.tick()          // prime the first reading
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    func menusChanged() { buildMenu() }

    // MARK: - Menu bar display (horizontal: down on the left, up on the right)
    private func render(down: Double, up: Double) {
        lastDown = down
        lastUp = up
        guard let button = statusItem?.button else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let color = NSColor.labelColor   // single colour for arrows and numbers

        let line = NSMutableAttributedString()
        func append(_ string: String) {
            line.append(NSAttributedString(string: string,
                attributes: [.font: font, .foregroundColor: color]))
        }

        switch displayMode {
        case "down":
            append(SpeedFormatter.padded(down) + " ↓")
        case "up":
            append(SpeedFormatter.padded(up) + " ↑")
        default:
            append(SpeedFormatter.padded(down) + " ↓")
            append("   " + SpeedFormatter.padded(up) + " ↑")
        }
        button.attributedTitle = line
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the menu is open
        timer = t
    }

    private func update() {
        guard let rate = monitor.tick() else { return }
        render(down: rate.downBytesPerSec, up: rate.upBytesPerSec)
    }

    // MARK: - Menu
    private func buildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let showHeader = NSMenuItem(title: "Show", action: nil, keyEquivalent: "")
        menu.addItem(showHeader)   // no action => disabled section label

        let modes: [(String, String)] = [
            ("Download only", "down"),
            ("Upload only", "up"),
            ("Both", "both"),
        ]
        for (title, value) in modes {
            let item = NSMenuItem(title: title,
                                  action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (value == displayMode) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let header = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        menu.addItem(header)   // no action => disabled section label

        for value in intervals {
            let item = NSMenuItem(title: "\(Int(value))s",
                                  action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (value == interval) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let speedTest = NSMenuItem(title: "Speed Test…",
                                   action: #selector(openSpeedTest), keyEquivalent: "")
        speedTest.target = self
        menu.addItem(speedTest)

        let activity = NSMenuItem(title: "Open Activity Monitor",
                                  action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)

        menu.addItem(.separator())

        // Shared Mac Speed section: module toggles, Start at Login, Quit.
        manager?.sharedMenuItems().forEach(menu.addItem)

        statusItem.menu = menu
    }

    // MARK: - Actions
    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        displayMode = value
        if let items = statusItem?.menu?.items {
            for item in items where item.representedObject is String {
                item.state = ((item.representedObject as? String) == value) ? .on : .off
            }
        }
        render(down: lastDown, up: lastUp)   // redraw immediately
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        interval = value
        if let items = statusItem?.menu?.items {
            for item in items where item.representedObject is Double {
                item.state = ((item.representedObject as? Double) == value) ? .on : .off
            }
        }
        monitor.reset()
        _ = monitor.tick()      // re-prime so the next reading is a clean delta
        startTimer()
    }

    @objc private func openSpeedTest() {
        if speedTestWC == nil { speedTestWC = SpeedTestWindowController() }
        speedTestWC?.present()
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}
