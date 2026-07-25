import Foundation
import CoreGraphics
import AppKit

/// Protocol for input control operations (DIP support).
protocol InputControlling: Sendable {
    func tap(x: Int, y: Int) async throws -> String
    func swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) async throws -> String
    func typeText(_ text: String, tapX: Int?, tapY: Int?) async throws -> String
    func clickViewMenuItem(_ itemName: String) async throws -> String
    func openAppViaSpotlight(_ appName: String) async throws -> String
    func getContentBounds() async throws -> InputController.ContentBounds
}

/// Posts CG events and AX actions directly from the companion app process.
/// This ensures the app's own Accessibility permission covers all input control,
/// instead of relying on osascript having permission.
actor InputController: InputControlling {
    private let scriptRunner: ScriptRunning

    init(scriptsPath: String) {
        self.scriptRunner = ScriptRunner(scriptsPath: scriptsPath)
    }

    init(scriptRunner: ScriptRunning) {
        self.scriptRunner = scriptRunner
    }

    struct ContentBounds {
        let contentX: Int
        let contentY: Int
        let contentWidth: Int
        let contentHeight: Int
    }

    // MARK: - Tap

    func tap(x: Int, y: Int) async throws -> String {
        let bounds = try await getContentBounds()
        guard x >= 0, x <= bounds.contentWidth, y >= 0, y <= bounds.contentHeight else {
            throw InputError.outOfBounds(x, y, bounds.contentWidth, bounds.contentHeight)
        }

        let absX = bounds.contentX + x
        let absY = bounds.contentY + y

        await activateIPhoneMirroring()

        let saved = saveCursor()
        let pt = CGPoint(x: absX, y: absY)

        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)

        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.tapDownUpDelay)
        up?.post(tap: .cghidEventTap)

        restoreCursor(saved)
        try await Task.sleep(nanoseconds: Constants.tapSettleDelay)

        return "Tapped at (\(x), \(y)) -> screen (\(absX), \(absY))"
    }

    // MARK: - Swipe

    func swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int = 300) async throws -> String {
        let bounds = try await getContentBounds()
        for (cx, cy) in [(x1, y1), (x2, y2)] {
            guard cx >= 0, cx <= bounds.contentWidth, cy >= 0, cy <= bounds.contentHeight else {
                throw InputError.outOfBounds(cx, cy, bounds.contentWidth, bounds.contentHeight)
            }
        }

        let absX1 = bounds.contentX + x1
        let absY1 = bounds.contentY + y1
        let absX2 = bounds.contentX + x2
        let absY2 = bounds.contentY + y2

        await activateIPhoneMirroring()

        let saved = saveCursor()
        let startPt = CGPoint(x: absX1, y: absY1)
        let endPt = CGPoint(x: absX2, y: absY2)
        let dx = Double(absX2 - absX1)
        let dy = Double(absY2 - absY1)
        let steps = 20
        let stepDelay = Double(durationMs) / 1000.0 / Double(steps)

        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: startPt, mouseButton: .left)
        down?.post(tap: .cghidEventTap)

        // Immediate kick to 30% - iOS needs early movement to distinguish drag from long-press
        let kickPt = CGPoint(x: Double(absX1) + dx * 0.3, y: Double(absY1) + dy * 0.3)
        let kick = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: kickPt, mouseButton: .left)
        kick?.post(tap: .cghidEventTap)

        for i in 1...steps {
            Thread.sleep(forTimeInterval: stepDelay)
            let f = 0.3 + 0.7 * (Double(i) / Double(steps))
            let mid = CGPoint(x: Double(absX1) + dx * f, y: Double(absY1) + dy * f)
            let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: mid, mouseButton: .left)
            drag?.post(tap: .cghidEventTap)
        }

        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: endPt, mouseButton: .left)
        up?.post(tap: .cghidEventTap)

        restoreCursor(saved)
        try await Task.sleep(nanoseconds: Constants.swipeSettleDelay)

        return "Swiped (\(x1),\(y1)) -> (\(x2),\(y2)) in \(durationMs)ms"
    }

    // MARK: - Type Text (native CGEvent keystrokes)

    func typeText(_ text: String, tapX: Int? = nil, tapY: Int? = nil) async throws -> String {
        if let x = tapX, let y = tapY {
            _ = try await tap(x: x, y: y)
            try await Task.sleep(nanoseconds: Constants.pageSwipeDelay)
        }

        await activateIPhoneMirroring()
        postKeystrokes(text)

        return "Typed: \(text)"
    }

    // MARK: - View Menu Actions (home, app switcher, spotlight)

    func clickViewMenuItem(_ itemName: String) async throws -> String {
        await activateIPhoneMirroring()
        Thread.sleep(forTimeInterval: Constants.menuOpenDelay)

        guard let pid = await iPhoneMirroringPID() else {
            throw InputError.windowNotFound
        }

        return try AccessibilityHelper.clickViewMenuItem(itemName, pid: pid)
    }

    // MARK: - Open App via Spotlight

    func openAppViaSpotlight(_ appName: String) async throws -> String {
        // Open Spotlight via View menu
        _ = try await clickViewMenuItem("Spotlight")
        try await Task.sleep(nanoseconds: Constants.spotlightOpenDelay)

        // Type the app name
        postKeystrokes(appName)
        try await Task.sleep(nanoseconds: Constants.spotlightSearchDelay)

        // Press Return to open
        postKeyCode(36) // Return

        return "Opened: \(appName) (spotlight)"
    }

    // MARK: - Content Bounds

    func getContentBounds() async throws -> ContentBounds {
        // Use native CGWindow API - no child process, no TCC inheritance issues
        if let bounds = nativeContentBounds() {
            return bounds
        }
        // Fallback: shell script (works when Terminal has Screen Recording permission)
        let result = try await scriptRunner.run(script: "find-window.sh")
        let json = result.stdout
        guard let cx = parseIntField(json, field: "content_x"),
              let cy = parseIntField(json, field: "content_y"),
              let cw = parseIntField(json, field: "content_width"),
              let ch = parseIntField(json, field: "content_height")
        else {
            throw InputError.windowNotFound
        }
        return ContentBounds(contentX: cx, contentY: cy, contentWidth: cw, contentHeight: ch)
    }

    private func nativeContentBounds() -> ContentBounds? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in list {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "iPhone Mirroring",
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            var rect = CGRect.zero
            CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect)
            guard rect.width > 100, rect.height > 100 else { continue }

            // ponytail: rough percentage bezels; port find-window.sh's alpha scan if
            // native-path tap accuracy ever matters more than avoiding the child process
            let mx = Int(rect.width * 0.06)
            let mt = Int(rect.height * 0.09)
            let mb = Int(rect.height * 0.04)

            return ContentBounds(
                contentX: Int(rect.minX) + mx,
                contentY: Int(rect.minY) + mt,
                contentWidth: Int(rect.width) - mx * 2,
                contentHeight: Int(rect.height) - mt - mb
            )
        }
        return nil
    }

    private func parseIntField(_ json: String, field: String) -> Int? {
        guard let range = json.range(of: "\"\(field)\":") else { return nil }
        let after = json[range.upperBound...]
        let numStr = after.prefix(while: { $0.isNumber || $0 == "-" })
        return Int(numStr)
    }

    // MARK: - Native Keystroke Posting

    private func postKeystrokes(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for char in text.unicodeScalars {
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(char.value)])
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(char.value)])
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: Constants.keystrokeDelay)
        }
    }

    private func postKeyCode(_ keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    @MainActor
    private func activateIPhoneMirroring() {
        let apps = NSWorkspace.shared.runningApplications
        if let im = apps.first(where: { $0.bundleIdentifier == Constants.iphoneMirroringBundleId }) {
            im.activate(options: .activateIgnoringOtherApps)
        }
        Thread.sleep(forTimeInterval: Constants.activateDelay)
    }

    @MainActor
    private func iPhoneMirroringPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == Constants.iphoneMirroringBundleId })?
            .processIdentifier
    }

    private func saveCursor() -> CGPoint {
        guard let event = CGEvent(source: nil) else { return .zero }
        return event.location
    }

    private func restoreCursor(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }
}

enum InputError: LocalizedError {
    case outOfBounds(Int, Int, Int, Int)
    case windowNotFound
    case menuNotFound(String)

    var errorDescription: String? {
        switch self {
        case .outOfBounds(let x, let y, let w, let h):
            return "Coordinates (\(x), \(y)) out of bounds (\(w)x\(h))"
        case .windowNotFound:
            return "iPhone Mirroring window not found. Is iPhone Mirroring open?"
        case .menuNotFound(let msg):
            return msg
        }
    }
}
