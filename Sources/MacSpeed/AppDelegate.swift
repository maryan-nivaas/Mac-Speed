import AppKit

/// A self-contained menu bar feature that can be switched on and off at runtime.
protocol BarModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var moduleDescription: String { get }
    var symbolName: String { get }
    func start(manager: AppDelegate)
    func stop()
    /// Called when module enablement changes so persistent menus can refresh.
    func menusChanged()
}

/// Owns the modules, their order, the shared settings menu, and the Settings window.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var modules: [BarModule] = []
    /// Module ids, leftmost in the menu bar first. Persisted.
    @Published private(set) var order: [String] = []
    private var startedIDs: Set<String> = []
    private var fallbackItem: NSStatusItem?
    private var settingsWC: SettingsWindowController?

    private let orderKey = "module.order"

    func applicationDidFinishLaunching(_ notification: Notification) {
        modules = [MusicModule(), SpeedModule()]
        // Saved order first, then any modules added since (future features).
        let saved = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        let known = modules.map(\.id)
        order = saved.filter(known.contains) + known.filter { !saved.contains($0) }
        applyLayout()
    }

    func module(withID id: String) -> BarModule? {
        modules.first { $0.id == id }
    }

    // MARK: - Enablement (persisted; default on)

    private func enabledKey(_ id: String) -> String { "module.\(id).enabled" }

    func isEnabled(_ module: BarModule) -> Bool { isEnabled(id: module.id) }

    func isEnabled(id: String) -> Bool {
        UserDefaults.standard.object(forKey: enabledKey(id)) as? Bool ?? true
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(enabled, forKey: enabledKey(id))
        applyLayout()
    }

    // MARK: - Ordering

    func moveModule(fromOffsets: IndexSet, toOffset: Int) {
        objectWillChange.send()
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        UserDefaults.standard.set(order, forKey: orderKey)
        applyLayout()
    }

    func moveModule(id: String, up: Bool) {
        guard let index = order.firstIndex(of: id) else { return }
        let target = up ? index - 1 : index + 1
        guard order.indices.contains(target) else { return }
        objectWillChange.send()
        order.swapAt(index, target)
        UserDefaults.standard.set(order, forKey: orderKey)
        applyLayout()
    }

    // MARK: - Layout

    /// Rebuilds every status item so the bar matches `order` and enablement.
    func applyLayout() {
        for module in modules where startedIDs.contains(module.id) { module.stop() }
        startedIDs.removeAll()
        clearSavedStatusPositions()
        // macOS places the most recently created status item leftmost, so we
        // create in reverse: order[0] is created last and ends up leftmost.
        for id in order.reversed() {
            guard let module = module(withID: id), isEnabled(id: id) else { continue }
            module.start(manager: self)
            startedIDs.insert(id)
        }
        updateFallbackItem()
        for module in modules where startedIDs.contains(module.id) { module.menusChanged() }
    }

    /// Drop pinned positions (from Cmd-dragging) so creation order wins.
    private func clearSavedStatusPositions() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSStatusItem Preferred Position") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Shared settings menu

    /// Fresh items every call — NSMenuItems cannot be shared between menus.
    func sharedMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        items.append(settings)

        let modulesMenu = NSMenu()
        for module in modules {
            let item = NSMenuItem(title: module.title,
                                  action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.id
            item.state = isEnabled(module) ? .on : .off
            modulesMenu.addItem(item)
        }
        let modulesItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
        modulesItem.submenu = modulesMenu
        items.append(modulesItem)

        let login = NSMenuItem(title: "Start at Login",
                               action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        items.append(login)

        items.append(.separator())

        let quit = NSMenuItem(title: "Quit Mac Speed", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        items.append(quit)

        return items
    }

    func sharedMenu() -> NSMenu {
        let menu = NSMenu()
        sharedMenuItems().forEach(menu.addItem)
        return menu
    }

    // MARK: - Actions

    @objc func openSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController(manager: self) }
        settingsWC?.present()
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setEnabled(id, !isEnabled(id: id))
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Fallback icon so the app stays reachable with all modules off

    private func updateFallbackItem() {
        if !startedIDs.isEmpty {
            if let item = fallbackItem { NSStatusBar.system.removeStatusItem(item) }
            fallbackItem = nil
            return
        }
        if fallbackItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "slider.horizontal.3",
                                         accessibilityDescription: "Mac Speed")
            fallbackItem = item
        }
        fallbackItem?.menu = sharedMenu()
    }
}
