import AppKit
import SwiftUI

/// Captures the next key the user presses, system-wide within this app's own window.
final class KeyRecorder: ObservableObject {
    private var monitor: Any?

    func start(completion: @escaping (UInt16, String) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            completion(UInt16(event.keyCode), Self.label(for: event))
            self?.stop()
            return nil // swallow so the keystroke doesn't type into the settings window
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func label(for event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty, chars != " " {
            return chars
        }
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default: return "Key Code \(event.keyCode)"
        }
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var manager: AppDelegate
    @ObservedObject private var hotkeySettings: HotkeySettings
    @StateObject private var recorder = KeyRecorder()
    @State private var isRecording = false
    @State private var isAccessibilityTrusted = true
    @State private var duplicateKeyMessage: String?

    init(manager: AppDelegate) {
        self.manager = manager
        self.hotkeySettings = manager.hotkeyManager.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Each key can be given its own set of click and hold actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: startRecording) {
                    Label(isRecording ? "Press any key…" : "Add Hotkey…", systemImage: "plus")
                }
                .disabled(isRecording)
            }

            if let duplicateKeyMessage {
                Text(duplicateKeyMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !hotkeySettings.bindings.isEmpty && !isAccessibilityTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility permission needed")
                        .font(.callout.weight(.semibold))
                    Text("Mac Speed needs Accessibility access to detect these keys system-wide, even when it isn't the active app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings…") {
                        manager.hotkeyManager.requestAccessibilityPermission()
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.14)))
            }

            if hotkeySettings.bindings.isEmpty {
                Text("No hotkeys yet. Click “Add Hotkey…”, then press any key on your keyboard.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(hotkeySettings.bindings) { binding in
                    HotkeyBindingRow(
                        binding: bindingProxy(for: binding.id),
                        onDelete: { removeBinding(binding.id) }
                    )
                }
            }
        }
        .onAppear { isAccessibilityTrusted = manager.hotkeyManager.isAccessibilityTrusted }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let trusted = manager.hotkeyManager.isAccessibilityTrusted
            if trusted != isAccessibilityTrusted {
                isAccessibilityTrusted = trusted
                applyConfig()
            }
        }
    }

    private func bindingProxy(for id: UUID) -> Binding<HotkeyBinding> {
        Binding(
            get: {
                hotkeySettings.bindings.first(where: { $0.id == id })
                    ?? HotkeyBinding(keyCode: 0, keyLabel: "")
            },
            set: { newValue in
                guard let index = hotkeySettings.bindings.firstIndex(where: { $0.id == id }) else { return }
                hotkeySettings.bindings[index] = newValue
                applyConfig()
            }
        )
    }

    private func removeBinding(_ id: UUID) {
        hotkeySettings.removeBinding(id: id)
        applyConfig()
    }

    private func startRecording() {
        isRecording = true
        duplicateKeyMessage = nil
        recorder.start { keyCode, label in
            isRecording = false
            if hotkeySettings.addBinding(keyCode: keyCode, keyLabel: label) == nil {
                duplicateKeyMessage = "“\(label)” is already assigned to another hotkey."
            } else {
                applyConfig()
            }
        }
    }

    private func applyConfig() {
        manager.hotkeyManager.applyCurrentConfig()
    }
}

private struct HotkeyBindingRow: View {
    @Binding var binding: HotkeyBinding
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(binding.keyLabel)
                    .font(.body.weight(.semibold))
                Toggle("", isOn: $binding.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ForEach(hotkeySupportedClickCounts, id: \.self) { count in
                HStack {
                    Text(clickLabel(for: count))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { binding.clickActions[count] ?? HotkeyAction.none },
                        set: { binding.clickActions[count] = $0 }
                    )) {
                        ForEach(HotkeyAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            Divider()

            HStack {
                Text("Hold key down")
                Spacer()
                Picker("", selection: $binding.holdAction) {
                    ForEach(HotkeyAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Text("Holding for about \(String(format: "%.1f", binding.holdThreshold))s triggers the hold action instead of counting as a click.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .opacity(binding.enabled ? 1 : 0.5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func clickLabel(for count: Int) -> String {
        switch count {
        case 1: return "Single click"
        case 2: return "Double click"
        case 3: return "Triple click"
        default: return "\(count)× click"
        }
    }
}
