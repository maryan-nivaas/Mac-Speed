import AppKit

// A small panel that runs a speed test and shows live download/upload figures.
// Separate from the menu bar readout, which keeps showing live throughput.
final class SpeedTestWindowController: NSWindowController, NSWindowDelegate {

    private var test: SpeedTest?
    private var downValue = NSTextField(labelWithString: "—")
    private var upValue = NSTextField(labelWithString: "—")
    private var statusLabel = NSTextField(labelWithString: "")
    private var runButton = NSButton(title: "Run again", target: nil, action: nil)

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Speed Test"
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.delegate = self
        buildUI()
    }

    private func row(_ caption: String, _ value: NSTextField, y: CGFloat) -> [NSView] {
        let cap = NSTextField(labelWithString: caption)
        cap.frame = NSRect(x: 24, y: y, width: 120, height: 30)
        cap.font = NSFont.systemFont(ofSize: 13)
        cap.textColor = .secondaryLabelColor
        value.frame = NSRect(x: 150, y: y, width: 146, height: 30)
        value.alignment = .right
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        return [cap, value]
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        statusLabel.frame = NSRect(x: 24, y: 186, width: 272, height: 20)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        row("Download", downValue, y: 132).forEach { content.addSubview($0) }
        row("Upload", upValue, y: 92).forEach { content.addSubview($0) }

        let unit = NSTextField(labelWithString: "Mbps")
        unit.frame = NSRect(x: 150, y: 66, width: 146, height: 16)
        unit.alignment = .right
        unit.font = NSFont.systemFont(ofSize: 11)
        unit.textColor = .tertiaryLabelColor
        content.addSubview(unit)

        runButton.frame = NSRect(x: 110, y: 18, width: 100, height: 30)
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = #selector(runTapped)
        content.addSubview(runButton)
    }

    @objc private func runTapped() { runTest() }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        runTest()
    }

    private func runTest() {
        test?.abort()
        runButton.isEnabled = false
        downValue.stringValue = "…"
        upValue.stringValue = "…"
        statusLabel.stringValue = "Testing download…"

        let t = SpeedTest()
        t.onProgress = { [weak self] phase, mbps in
            guard let self else { return }
            let text = String(format: "%.1f", mbps)
            switch phase {
            case .download:
                self.statusLabel.stringValue = "Testing download…"
                self.downValue.stringValue = text
            case .upload:
                self.statusLabel.stringValue = "Testing upload…"
                self.upValue.stringValue = text
            case .done:
                break
            }
        }
        t.onFinished = { [weak self] down, up in
            guard let self else { return }
            self.statusLabel.stringValue = "Done"
            self.downValue.stringValue = String(format: "%.1f", down)
            self.upValue.stringValue = String(format: "%.1f", up)
            self.runButton.isEnabled = true
        }
        test = t
        t.start()
    }

    func windowWillClose(_ notification: Notification) {
        test?.abort()
        test = nil
    }
}
