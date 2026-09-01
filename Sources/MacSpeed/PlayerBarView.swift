import AppKit

/// Horizontally scrolls its text when wider than the view; static otherwise.
final class MarqueeView: NSView {
    private var timer: Timer?
    private var offset: CGFloat = 0
    private let gap: CGFloat = 14
    private let speed: CGFloat = 0.5   // points per tick at 30fps

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Own layer + masking, otherwise drawing spills past our bounds
        // into the neighboring buttons inside the status bar button's layer.
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            offset = 0
            updateTimer()
            needsDisplay = true
        }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
         .foregroundColor: NSColor.labelColor]
    }

    private var textWidth: CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        guard textWidth > bounds.width else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.offset += self.speed
            if self.offset >= self.textWidth + self.gap { self.offset = 0 }
            self.needsDisplay = true
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        let ns = text as NSString
        let size = ns.size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2
        if size.width <= bounds.width {
            ns.draw(at: NSPoint(x: 0, y: y), withAttributes: attributes)
        } else {
            ns.draw(at: NSPoint(x: -offset, y: y), withAttributes: attributes)
            ns.draw(at: NSPoint(x: -offset + size.width + gap, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    deinit { timer?.invalidate() }
}

/// Menu-bar-style button: shows the system rounded highlight while pressed,
/// like Apple's own menu bar extras.
final class BarButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            let highlight = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: 4, yRadius: 4)
            NSColor.labelColor.withAlphaComponent(0.15).setFill()
            highlight.fill()
        }
        super.draw(dirtyRect)
    }
}

/// The 200px strip that lives inside the status item:
/// [artwork 20][marquee 96][play/pause 20] 6px [previous 20] 6px [next 20]
final class PlayerBarView: NSView {
    static let totalWidth: CGFloat = 200

    var onPlayPause: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onOpenPlayer: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?

    private let artworkView = NSImageView()
    private let marquee = MarqueeView()
    private let playPauseButton = BarButton()
    private let previousButton = BarButton()
    private let nextButton = BarButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let h = frameRect.height

        artworkView.frame = NSRect(x: 2, y: (h - 20) / 2, width: 20, height: 20)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 3
        artworkView.layer?.masksToBounds = true
        addSubview(artworkView)

        marquee.frame = NSRect(x: 26, y: 0, width: 96, height: h)
        addSubview(marquee)

        configure(playPauseButton, symbol: "play.fill", x: 126, height: h, action: #selector(playPauseTapped))
        configure(previousButton, symbol: "backward.end.fill", x: 152, height: h, action: #selector(previousTapped))
        configure(nextButton, symbol: "forward.end.fill", x: 178, height: h, action: #selector(nextTapped))

        showIdle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: NSButton, symbol: String, x: CGFloat, height: CGFloat, action: Selector) {
        button.frame = NSRect(x: x, y: 0, width: 20, height: height)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.image = Self.symbolImage(symbol)
        button.target = self
        button.action = action
        addSubview(button)
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        image?.isTemplate = true
        return image
    }

    func setPlaying(_ isPlaying: Bool) {
        playPauseButton.image = Self.symbolImage(isPlaying ? "pause.fill" : "play.fill")
    }

    func update(isPlaying: Bool, trackName: String, artwork: NSImage?) {
        playPauseButton.image = Self.symbolImage(isPlaying ? "pause.fill" : "play.fill")
        marquee.text = String(trackName.prefix(15))
        if let artwork {
            artworkView.image = artwork
        } else {
            artworkView.image = Self.symbolImage("music.note")
        }
        [playPauseButton, previousButton, nextButton].forEach { $0.isEnabled = true }
        alphaValue = 1
    }

    func showIdle() {
        playPauseButton.image = Self.symbolImage("play.fill")
        marquee.text = ""
        artworkView.image = Self.symbolImage("music.note")
        [playPauseButton, previousButton, nextButton].forEach { $0.isEnabled = false }
        alphaValue = 0.5
    }

    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func previousTapped() { onPrevious?() }
    @objc private func nextTapped() { onNext?() }

    // Clicks on the artwork / title (not on a button) bring the player app forward.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x < 126 { onOpenPlayer?() }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let menu = contextMenuProvider?() ?? nil else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
