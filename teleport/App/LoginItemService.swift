import Foundation
import ServiceManagement

struct LoginItemService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
