// Listen-only mouse event recorder: one JSON line per event.
//
// Used to capture REAL human input so gesture synthesis can be modeled on
// measured dynamics instead of guesses. The icon-drag recipe in the input
// engine was reverse-engineered from a recording made with this tool.
//
// Usage: event-logger <output.jsonl> [duration_seconds]

import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/event-log.jsonl"
let duration = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 90) : 90

FileManager.default.createFile(atPath: outPath, contents: nil)
guard let handle = FileHandle(forWritingAtPath: outPath) else {
    fputs("error: cannot open \(outPath)\n", stderr)
    exit(1)
}
var logHandle: FileHandle? = handle

let mask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.leftMouseUp.rawValue) |
    (1 << CGEventType.leftMouseDragged.rawValue) |
    (1 << CGEventType.mouseMoved.rawValue)

func name(_ type: CGEventType) -> String {
    switch type {
    case .leftMouseDown: return "down"
    case .leftMouseUp: return "up"
    case .leftMouseDragged: return "drag"
    case .mouseMoved: return "move"
    default: return "other\(type.rawValue)"
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    let loc = event.location
    let line = String(
        format: "{\"t\":\"%@\",\"ts\":%llu,\"x\":%.2f,\"y\":%.2f,\"dx\":%lld,\"dy\":%lld," +
            "\"click\":%lld,\"press\":%.3f}\n",
        name(type),
        event.timestamp,
        loc.x, loc.y,
        event.getIntegerValueField(.mouseEventDeltaX),
        event.getIntegerValueField(.mouseEventDeltaY),
        event.getIntegerValueField(.mouseEventClickState),
        event.getDoubleValueField(.mouseEventPressure)
    )
    if let data = line.data(using: .utf8) {
        logHandle?.write(data)
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: nil
) else {
    fputs("error: could not create event tap (needs Accessibility/Input Monitoring permission)\n", stderr)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
fputs("recording to \(outPath) for \(Int(duration))s\n", stderr)
CFRunLoopRunInMode(.defaultMode, duration, false)
try? handle.close()
logHandle = nil
