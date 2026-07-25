import Foundation
import AppKit

/// Encapsulates AX API traversal for menu bar interaction.
enum AccessibilityHelper {
    /// Click a menu item under the "View" menu of iPhone Mirroring.
    static func clickViewMenuItem(_ itemName: String, pid: pid_t) throws -> String {
        let appElement = AXUIElementCreateApplication(pid)

        // Get menu bar
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success else {
            throw InputError.menuNotFound("Cannot access menu bar")
        }
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        // Find "View" menu bar item
        var menuBarItems: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &menuBarItems) == .success,
              let items = menuBarItems as? [AXUIElement]
        else {
            throw InputError.menuNotFound("Cannot access menu bar items")
        }

        var viewMenuItem: AXUIElement?
        for item in items {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == "View" {
                viewMenuItem = item
                break
            }
        }

        guard let viewItem = viewMenuItem else {
            throw InputError.menuNotFound("View menu not found")
        }

        // Press the View menu to open it
        AXUIElementPerformAction(viewItem, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: Constants.menuOpenDelay)

        // Get the menu's children
        var menuRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(viewItem, kAXChildrenAttribute as CFString, &menuRef) == .success,
              let menus = menuRef as? [AXUIElement],
              let menu = menus.first
        else {
            throw InputError.menuNotFound("View menu has no submenu")
        }

        var menuChildren: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &menuChildren) == .success,
              let menuItems = menuChildren as? [AXUIElement]
        else {
            throw InputError.menuNotFound("Cannot access View menu items")
        }

        // Find and click the target item
        for menuItem in menuItems {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(menuItem, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == itemName {
                AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                return "\(itemName) activated"
            }
        }

        // Dismiss menu if item not found
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        throw InputError.menuNotFound("\(itemName) not found in View menu")
    }
}
