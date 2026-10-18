import AppKit
import Foundation

final class FocusCullAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .focusCullShowMainWindow, object: nil)
        }
        return true
    }
}

extension Notification.Name {
    static let focusCullShowMainWindow = Notification.Name("FocusCullShowMainWindow")
}
