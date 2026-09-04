import AppKit
import ApplicationServices
import CoreGraphics

/// Listens system-wide for a set of user-chosen keys and turns click counts and
/// long-presses into media actions. Uses a listen-only CGEventTap so keys keep
/// working normally everywhere else — they are only ever observed, never consumed.
final class HotkeyManager {
    let settings = HotkeySettings()

    /// Set by AppDelegate to actually perform play/pause/mute/next/previous.
    var performAction: ((HotkeyAction) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Per-key click/hold tracking, since several keys can be watched at once.
    private final class GestureState {
        var isKeyDown = false
        var holdFired = false
        var holdTimer: Timer?
        var clickCount = 0
        var clickTimer: Timer?
    }
    private var gestureStates: [UInt16: GestureState] = [:]

    /// Call after `settings.bindings` changes to start/stop listening as needed.
    func applyCurrentConfig() {
        if settings.bindings.contains(where: { $0.enabled }) {
            start()
        } else {
            stop()
        }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system Accessibility permission dialog if not already trusted.
    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    manager.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        for state in gestureStates.values {
            state.holdTimer?.invalidate()
            state.clickTimer?.invalidate()
        }
        gestureStates.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard let binding = settings.bindings.first(where: { $0.keyCode == keyCode && $0.enabled }) else { return }
        // Ignore OS auto-repeat while the key is held; hold detection uses our own timer.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }

        let state = gestureStates[keyCode] ?? {
            let newState = GestureState()
            gestureStates[keyCode] = newState
            return newState
        }()

        switch type {
        case .keyDown: onKeyDown(binding: binding, state: state)
        case .keyUp: onKeyUp(binding: binding, state: state)
        default: break
        }
    }

    private func onKeyDown(binding: HotkeyBinding, state: GestureState) {
        guard !state.isKeyDown else { return }
        state.isKeyDown = true
        state.holdFired = false

        state.holdTimer?.invalidate()
        state.holdTimer = Timer.scheduledTimer(withTimeInterval: binding.holdThreshold, repeats: false) { [weak self, weak state] _ in
            guard let self, let state else { return }
            state.holdFired = true
            state.clickTimer?.invalidate()
            state.clickCount = 0
            self.dispatch(binding.holdAction)
        }
    }

    private func onKeyUp(binding: HotkeyBinding, state: GestureState) {
        state.holdTimer?.invalidate()
        state.holdTimer = nil
        state.isKeyDown = false

        if state.holdFired {
            state.holdFired = false
            return
        }

        state.clickCount += 1
        state.clickTimer?.invalidate()
        state.clickTimer = Timer.scheduledTimer(withTimeInterval: binding.clickWindow, repeats: false) { [weak self, weak state] _ in
            guard let self, let state else { return }
            let count = state.clickCount
            state.clickCount = 0
            if let action = binding.clickActions[count] {
                self.dispatch(action)
            }
        }
    }

    private func dispatch(_ action: HotkeyAction) {
        guard action != .none else { return }
        DispatchQueue.main.async { [weak self] in self?.performAction?(action) }
    }
}
