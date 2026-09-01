import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Modules")
                    .font(.title3.bold())
                Text("Switch features on or off and reorder them. The top module appears leftmost in the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 8)

            List {
                ForEach(manager.order, id: \.self) { id in
                    if let module = manager.module(withID: id) {
                        row(for: module)
                    }
                }
                .onMove { manager.moveModule(fromOffsets: $0, toOffset: $1) }
            }
            .scrollContentBackground(.hidden)

            Text("Tip: drag a row, or use the arrows, to change its position in the bar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding([.horizontal, .bottom], 20)
                .padding(.top, 4)
        }
        .frame(width: 480, height: 340)
    }

    private func row(for module: BarModule) -> some View {
        let id = module.id
        let index = manager.order.firstIndex(of: id) ?? 0
        return HStack(spacing: 12) {
            Image(systemName: module.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.body.weight(.semibold))
                Text(module.moduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(spacing: 2) {
                Button { manager.moveModule(id: id, up: true) } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .opacity(index == 0 ? 0.25 : 0.7)

                Button { manager.moveModule(id: id, up: false) } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(index == manager.order.count - 1)
                .opacity(index == manager.order.count - 1 ? 0.25 : 0.7)
            }

            Toggle("", isOn: Binding(
                get: { manager.isEnabled(id: id) },
                set: { manager.setEnabled(id, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init(manager: AppDelegate) {
        let hosting = NSHostingController(rootView: SettingsView(manager: manager))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Mac Speed Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
