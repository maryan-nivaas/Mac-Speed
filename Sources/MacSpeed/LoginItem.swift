import ServiceManagement
import Foundation

// Thin wrapper over the modern macOS 13+ login-item API. No helper bundle and
// nothing to configure in System Settings by hand.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("Mac Speed login-item change failed: \(error.localizedDescription)")
            return false
        }
    }
}
