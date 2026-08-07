// Character -> virtual keycode mapping for the active keyboard layout.
//
// iPhone Mirroring forwards the raw VIRTUAL KEYCODE of a key event to the phone
// and ignores any unicode payload set with CGEvent.keyboardSetUnicodeString.
// Typing therefore has to find the real key (plus modifiers) that produces each
// character on the user's current layout - exactly what System Events does
// internally, done here natively so it costs no extra process.

import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct KeyStroke {
    let code: CGKeyCode
    let flags: CGEventFlags
}

/// Build character -> keystroke by asking the active layout what every
/// keycode/modifier combination produces. Lower modifier combos are inserted
/// first and never overwritten, so 'a' resolves to plain A, not some
/// option-combination that happens to produce the same glyph.
func buildKeyMap() -> [Character: KeyStroke] {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return [:] }
    let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data

    // (carbon modifier bits for UCKeyTranslate, CGEventFlags for posting)
    let combos: [(UInt32, CGEventFlags)] = [
        (0, []),
        (UInt32(shiftKey >> 8), .maskShift),
        (UInt32(optionKey >> 8), .maskAlternate),
        (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate])
    ]

    var map: [Character: KeyStroke] = [:]
    data.withUnsafeBytes { raw in
        guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
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
                let s = String(utf16CodeUnits: chars, count: length)
                guard let ch = s.first, !ch.isNewline, ch != "\u{0}" else { continue }
                if map[ch] == nil {
                    map[ch] = KeyStroke(code: CGKeyCode(code), flags: cgFlags)
                }
            }
        }
    }

    // Whitespace and control keys are not produced by UCKeyTranslate above.
    map["\n"] = KeyStroke(code: 36, flags: [])
    map["\t"] = KeyStroke(code: 48, flags: [])
    map[" "] = KeyStroke(code: 49, flags: [])
    return map
}
