// Autostart.swift — start up at login.

import Foundation
import ServiceManagement

@MainActor
enum Autostart {

    static var an: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Returns whether it worked.
    @discardableResult
    static func setzen(_ an: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if an {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
