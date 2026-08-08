import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox

// Just over the length limit after porting the layout keymap; the keymap belongs
// with the input engine rather than in a separate file.
// swiftlint:disable file_length

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

    /// Convert a 0-1000 normalized coordinate to a content-pixel offset, clamped to
    /// [0, limit]. The model works in a resolution-independent 0-1000 space; anything
    /// outside it (a mild over/undershoot) clamps to the edge rather than erroring.
    private static func contentPixel(_ normalized: Int, limit: Int) -> Int {
        min(max(normalized * limit / 1000, 0), limit)
    }

    func tap(x: Int, y: Int) async throws -> String {
        let bounds = try await getContentBounds()
        // x/y are normalized 0-1000 (resolution-independent). Map to content pixels
        // and clamp, so a mild over/undershoot lands at the edge instead of erroring.
        let absX = bounds.contentX + Self.contentPixel(x, limit: bounds.contentWidth)
        let absY = bounds.contentY + Self.contentPixel(y, limit: bounds.contentHeight)

        let session = await beginSession()
        let pt = CGPoint(x: absX, y: absY)

        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)

        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.tapDownUpDelay)
        up?.post(tap: .cghidEventTap)

        await endSession(session)
        try await Task.sleep(nanoseconds: Constants.tapSettleDelay)

        return "Tapped at (\(x), \(y)) -> screen (\(absX), \(absY))"
    }

    // MARK: - Swipe

    func swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int = 300) async throws -> String {
        let bounds = try await getContentBounds()
        // Normalized 0-1000 endpoints -> content pixels (clamped).
        let absX1 = bounds.contentX + Self.contentPixel(x1, limit: bounds.contentWidth)
        let absY1 = bounds.contentY + Self.contentPixel(y1, limit: bounds.contentHeight)
        let absX2 = bounds.contentX + Self.contentPixel(x2, limit: bounds.contentWidth)
        let absY2 = bounds.contentY + Self.contentPixel(y2, limit: bounds.contentHeight)

        let session = await beginSession()
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

        await endSession(session)
        try await Task.sleep(nanoseconds: Constants.swipeSettleDelay)

        return "Swiped (\(x1),\(y1)) -> (\(x2),\(y2)) in \(durationMs)ms"
    }

    // MARK: - Type Text (native CGEvent keystrokes)

    func typeText(_ text: String, tapX: Int? = nil, tapY: Int? = nil) async throws -> String {
        if let x = tapX, let y = tapY {
            _ = try await tap(x: x, y: y)
            try await Task.sleep(nanoseconds: Constants.pageSwipeDelay)
        }

        let session = await beginSession()
        postKeystrokes(text)
        await endSession(session)

        return "Typed: \(text)"
    }

    // MARK: - View Menu Actions (home, app switcher, spotlight)

    func clickViewMenuItem(_ itemName: String) async throws -> String {
        let session = await beginSession()
        do {
            let result = try await clickViewMenuItemCore(itemName)
            await endSession(session)
            return result
        } catch {
            await endSession(session)
            throw error
        }
    }

    /// Assumes iPhone Mirroring is already active (inside an input session).
    private func clickViewMenuItemCore(_ itemName: String) async throws -> String {
        Thread.sleep(forTimeInterval: Constants.menuOpenDelay)

        guard let pid = await iPhoneMirroringPID() else {
            throw InputError.windowNotFound
        }

        return try AccessibilityHelper.clickViewMenuItem(itemName, pid: pid)
    }

    // MARK: - Open App via Spotlight

    func openAppViaSpotlight(_ appName: String) async throws -> String {
        let session = await beginSession()
        do {
            // Open Spotlight via View menu
            _ = try await clickViewMenuItemCore("Spotlight")
            try await Task.sleep(nanoseconds: Constants.spotlightOpenDelay)

            // Type the app name
            postKeystrokes(appName)
            try await Task.sleep(nanoseconds: Constants.spotlightSearchDelay)

            // Press Return to open
            postKeyCode(36) // Return
            await endSession(session)
        } catch {
            await endSession(session)
            throw error
        }

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

    // iPhone Mirroring forwards the raw VIRTUAL KEYCODE and ignores any unicode
    // payload from keyboardSetUnicodeString, so typing must resolve each character
    // to the real key + modifiers on the active layout and post keycode events.
    // (The previous unicode approach silently typed nothing into the phone.)
    // TIS/keyboard-layout APIs assert they run on the main thread; this actor's
    // executor is a background thread, so hop to main to build the map (it crashed
    // with a dispatch_assert_queue SIGTRAP otherwise).
    private static let keyMap: [Character: KeyStroke] = {
        Thread.isMainThread ? buildLayoutKeyMap() : DispatchQueue.main.sync(execute: buildLayoutKeyMap)
    }()

    private func postKeystrokes(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for char in text {
            guard let stroke = Self.keyMap[char] else {
                NSLog("[Companion] typeText: no key for %@ on active layout, skipping", String(char))
                continue
            }
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: stroke.code, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: stroke.code, keyDown: false)
            keyDown?.flags = stroke.flags
            keyUp?.flags = stroke.flags
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

    // MARK: - Input Session (steal cursor/focus politely, give both back)

    private struct InputSession {
        let cursor: CGPoint
        let previousApp: NSRunningApplication?
    }

    /// Waits for the user to stop typing/moving the mouse, saves cursor position and
    /// frontmost app, then activates iPhone Mirroring.
    private func beginSession() async -> InputSession {
        waitForUserIdle()
        return await openSessionOnMain()
    }

    @MainActor
    private func openSessionOnMain() -> InputSession {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        let previous = NSWorkspace.shared.frontmostApplication
        let apps = NSWorkspace.shared.runningApplications
        if let im = apps.first(where: { $0.bundleIdentifier == Constants.iphoneMirroringBundleId }) {
            im.activate(options: .activateIgnoringOtherApps)
        }
        Thread.sleep(forTimeInterval: Constants.activateDelay)
        return InputSession(cursor: cursor, previousApp: previous)
    }

    /// Epoch of our last synthetic post - lets waitForUserIdle tell our events from the user's.
    private var lastSyntheticPost = Date.distantPast

    /// Restores cursor position and reactivates whatever app the user had frontmost,
    /// then stamps the time so the next session skips the idle wait for our own events.
    private func endSession(_ session: InputSession) async {
        await closeSessionOnMain(session)
        lastSyntheticPost = Date()
    }

    @MainActor
    private func closeSessionOnMain(_ session: InputSession) {
        Thread.sleep(forTimeInterval: Constants.sessionCloseDelay)
        CGWarpMouseCursorPosition(session.cursor)
        if let previous = session.previousApp,
           previous.bundleIdentifier != Constants.iphoneMirroringBundleId {
            previous.activate(options: .activateIgnoringOtherApps)
        }
    }

    /// Blocks (in actor context, off the main thread) until user input has been quiet
    /// for userIdleThreshold, or userIdleTimeout elapses. Skips waiting when the most
    /// recent HID event is no newer than our own last synthetic post.
    private func waitForUserIdle() {
        let inputTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .keyDown, .scrollWheel]
        let deadline = Date().addingTimeInterval(Constants.userIdleTimeout)
        while Date() < deadline {
            let idle = inputTypes
                .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
                .min() ?? .infinity
            if idle >= Constants.userIdleThreshold { break }
            let lastEventAt = Date().addingTimeInterval(-idle)
            if lastEventAt.timeIntervalSince(lastSyntheticPost) <= Constants.syntheticEventSlack { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func iPhoneMirroringPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == Constants.iphoneMirroringBundleId })?
            .processIdentifier
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

struct KeyStroke {
    let code: CGKeyCode
    let flags: CGEventFlags
}

/// Character -> keystroke for the ACTIVE keyboard layout, so typing works on
/// AZERTY/QWERTZ/etc, not only US-QWERTY. Ported from the repo's input engine;
/// iPhone Mirroring reads the virtual keycode, never the unicode payload.
private func buildLayoutKeyMap() -> [Character: KeyStroke] {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return [:] }
    let layoutData = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data

    // (carbon modifier bits for UCKeyTranslate, CGEventFlags for posting)
    let combos: [(UInt32, CGEventFlags)] = [
        (0, []),
        (UInt32(shiftKey >> 8), .maskShift),
        (UInt32(optionKey >> 8), .maskAlternate),
        (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate])
    ]

    var map: [Character: KeyStroke] = [:]
    layoutData.withUnsafeBytes { rawBuffer in
        guard let layout = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
        for (carbonMods, cgFlags) in combos {
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), carbonMods,
                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length == 1 else { continue }
                let glyphString = String(utf16CodeUnits: chars, count: length)
                guard let glyph = glyphString.first, !glyph.isNewline, glyph != "\u{0}" else { continue }
                if map[glyph] == nil {
                    map[glyph] = KeyStroke(code: CGKeyCode(code), flags: cgFlags)
                }
            }
        }
    }

    // Whitespace/control keys are not produced by UCKeyTranslate above.
    map["\n"] = KeyStroke(code: 36, flags: [])
    map["\t"] = KeyStroke(code: 48, flags: [])
    map[" "] = KeyStroke(code: 49, flags: [])
    return map
}
