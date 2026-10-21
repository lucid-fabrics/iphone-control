import AppKit
import Carbon.HIToolbox

/// iPhone Mirroring View-menu actions, driven by their Cmd+digit shortcuts.
/// Menu titles are localized ("View", "Spotlight"...), so nothing here matches a title.
enum ViewShortcut: Int {
    case homeScreen = 1
    case appSwitcher = 2
    case spotlight = 3

    /// Key code and flags that produce Cmd+<digit> on the active keyboard layout.
    /// On layouts where the digit needs Shift (AZERTY), Shift is added; falls back to
    /// the ANSI digit row if the layout cannot be queried.
    func keyStroke() -> (code: CGKeyCode, flags: CGEventFlags) {
        let ansi: [CGKeyCode] = [18, 19, 20]
        let fallback = (code: ansi[rawValue - 1], flags: CGEventFlags.maskCommand)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return fallback }
        let layout = unsafeBitCast(dataRef, to: CFData.self)
        let target = Character(String(rawValue))
        for (shift, flags) in [(0, CGEventFlags.maskCommand), (2, [.maskCommand, .maskShift])] {
            for code in 0..<UInt16(128) where Self.character(for: code, shiftState: UInt32(shift), layout: layout) == target {
                return (CGKeyCode(code), flags)
            }
        }
        return fallback
    }

    private static func character(for code: UInt16, shiftState: UInt32, layout: CFData) -> Character? {
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, code, UInt16(kUCKeyActionDown), shiftState,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                           &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) else { return nil }
        return Character(scalar)
    }

    /// Posts the shortcut. Assumes iPhone Mirroring is already active (inside an input session).
    func post() {
        let (code, flags) = keyStroke()
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.keystrokeDelay)
        keyUp?.post(tap: .cghidEventTap)
    }
}
