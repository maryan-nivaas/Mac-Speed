import Foundation
import AppKit

/// An action the user can bind to a click-count or a key hold.
enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case none
    case play
    case pause
    case playPause
    case mute
    case next
    case previous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .play: return "Play"
        case .pause: return "Pause"
        case .playPause: return "Play / Pause"
        case .mute: return "Mute"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        }
    }
}

/// The number of consecutive presses that trigger an action. 1 = single click, 2 = double click, etc.
let hotkeySupportedClickCounts = [1, 2, 3, 4]

/// One independently-configured key: which key, what each click count does, and what holding it does.
/// Users can create several of these, each bound to a different key.
struct HotkeyBinding: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var enabled: Bool = true
    var keyCode: UInt16
    /// Human-readable label captured at record time, since key codes alone aren't display-friendly.
    var keyLabel: String
    var clickActions: [Int: HotkeyAction] = [1: .playPause]
    var holdAction: HotkeyAction = .none
    var holdThreshold: Double = 0.6
    var clickWindow: Double = 0.35
}

/// Persists the list of hotkey bindings and publishes changes for SwiftUI.
final class HotkeySettings: ObservableObject {
    @Published var bindings: [HotkeyBinding] {
        didSet { save() }
    }

    private let defaultsKey = "hotkey.bindings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([HotkeyBinding].self, from: data) {
            bindings = decoded
        } else {
            bindings = []
        }
    }

    /// Adds a new binding for `keyCode`, unless that key is already assigned.
    @discardableResult
    func addBinding(keyCode: UInt16, keyLabel: String) -> HotkeyBinding? {
        guard !bindings.contains(where: { $0.keyCode == keyCode }) else { return nil }
        let binding = HotkeyBinding(keyCode: keyCode, keyLabel: keyLabel)
        bindings.append(binding)
        return binding
    }

    func removeBinding(id: UUID) {
        bindings.removeAll { $0.id == id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
