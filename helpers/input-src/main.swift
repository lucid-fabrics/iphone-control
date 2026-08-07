// Native input engine for iphone-control.
//
// One process does the whole action: resolve the mirroring window, wait for the
// user to be idle, save cursor + frontmost app, activate mirroring, post events,
// restore cursor + focus. The shell path spawns bash + osascript per action
// (~300-500ms of pure overhead); this runs in ~15ms.
//
// Coordinates on the command line are CONTENT POINTS (origin = top-left of the
// iOS screen area), the same space as screenshots and every other command.
//
// Usage:
//   input tap <x> <y>
//   input doubletap <x> <y>
//   input longpress <x> <y> [holdMs]
//   input key <keycode> <flagsMask>
//   input scroll <x> <y> <dy>
//   input swipe <x1> <y1> <x2> <y2> [durationMs]
//   input drag <x1> <y1> <x2> <y2> [hoverMs] [viaX viaY]
//   input text <utf8-file-path>
//   input bounds                       print window JSON (find-window.sh shape)
//   input keyfor <char>                print "<keycode> <flagsRawValue>" for one
//                                       character on the ACTIVE layout (no phone
//                                       needed - pure macOS layout query)
//   input serve                        run as a resident daemon on a unix socket:
//                                       warm Vision OCR, native capture, one input
//                                       session held across commands (idle-closed)
//   input send <verb> [args...]        send one command to the daemon, starting it
//                                       if needed; falls back is the caller's job
//
// Global flags (before the verb):
//   --no-restore    leave focus on iPhone Mirroring (for chained actions)
//   --no-idle-wait  do not wait for the user to stop typing/moving

import AppKit
import CoreGraphics
import Foundation

// MARK: - Tunables (mirror helpers/common.sh)

enum Tune {
    static let tapDelay = 0.02
    static let keyDelay = 0.015
    static let activateTimeout = 0.5
    static let sessionCloseDelay = 0.05
    static let userIdleThreshold = 0.3
    static let userIdleTimeout = 5.0
    static let syntheticSlack = 0.2
    static let swipeSteps = 20
    static let swipeKickFactor = 0.3
    static let scrollPointsPerLine = 3.0
    static let scrollLinesPerEvent: Int32 = 3
    static let iconDragSpeed = 0.45          // px per ms
    static let iconDragStepMs = 8.0
    static let iconDragLiftHold = 0.17
    static let bundleID = "com.apple.ScreenContinuity"
    static let cachePath = "/tmp/iphone-mirror-window.json"
    static let cacheKeyPath = "/tmp/iphone-mirror-window.key"
    static let stampPath = "/tmp/iphone-control-last-post"
    static let cacheTTL: TimeInterval = 30
    static let socketPath = "/tmp/iphone-control-daemon.sock"
    static let daemonSessionIdle = 1.5    // close the input session after this quiet
    static let daemonExitIdle = 300.0     // daemon exits after this long unused
    static let stillSize = 32             // downscale width for stillness compare
    static let stillTolerance = 2.0       // mean abs pixel diff considered unchanged
    static let stillInterval = 0.12
    static let stillLeadIn = 0.2
    static let stillConfirmations = 2
}

/// Set once a session is open. Any exit path - die(), a signal, a Swift trap
/// unwinding through atexit - must release the mouse button and hand back the
/// cursor and focus, or the user is left with a stuck global mouse-down.
var activeSession: Session?

func releaseAndRestore() {
    guard let s = activeSession else { return }
    activeSession = nil
    // Releasing at the last known point is safe even if no button is held.
    if let e = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp,
                       mouseCursorPosition: lastPoint, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    CGWarpMouseCursorPosition(s.cursor)
    if let prev = s.previousApp, prev.bundleIdentifier != Tune.bundleID {
        prev.activate()
    }
}

func die(_ msg: String) -> Never {
    releaseAndRestore()
    fputs("Error: \(msg)\n", stderr)
    exit(1)
}

// MARK: - Input session

struct Session {
    let cursor: CGPoint
    let previousApp: NSRunningApplication?
}

var restoreState = true
var idleWaitEnabled = true

/// Blocks until real user input has been quiet, ignoring our own synthetic events.
func waitForUserIdle() {
    guard idleWaitEnabled else { return }
    let lastPost = (try? String(contentsOfFile: Tune.stampPath, encoding: .utf8))
        .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .keyDown, .scrollWheel]
    let deadline = Date().addingTimeInterval(Tune.userIdleTimeout)
    while Date() < deadline {
        let idle = types
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? .infinity
        if idle >= Tune.userIdleThreshold { return }
        // A recent event that is our own previous post must not stall us.
        if Date().timeIntervalSince1970 - idle <= lastPost + Tune.syntheticSlack { return }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

func beginSession() -> Session {
    waitForUserIdle()
    let cursor = CGEvent(source: nil)?.location ?? .zero
    let previous = NSWorkspace.shared.frontmostApplication
    defer { activeSession = Session(cursor: cursor, previousApp: previous) }

    // Already frontmost (the common case mid-sequence): nothing to activate, so
    // no settle wait, and no focus to hand back at the end.
    if previous?.bundleIdentifier == Tune.bundleID {
        return Session(cursor: cursor, previousApp: nil)
    }
    guard let im = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == Tune.bundleID }) else {
        return Session(cursor: cursor, previousApp: previous)
    }
    im.activate()
    // Poll rather than sleeping a fixed worst case: activation usually lands in
    // ~10ms, and events posted before it do not reach the phone.
    let deadline = Date().addingTimeInterval(Tune.activateTimeout)
    while !im.isActive && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.005)
    }
    return Session(cursor: cursor, previousApp: previous)
}

func endSession(_ s: Session) {
    Thread.sleep(forTimeInterval: Tune.sessionCloseDelay)
    try? String(Date().timeIntervalSince1970)
        .write(toFile: Tune.stampPath, atomically: true, encoding: .utf8)
    activeSession = nil
    guard restoreState else { return }
    CGWarpMouseCursorPosition(s.cursor)
    guard let prev = s.previousApp, prev.bundleIdentifier != Tune.bundleID else { return }
    prev.activate()
    // activate() is a request to the window server. Exiting immediately can drop
    // it, leaving the user staring at iPhone Mirroring, so wait for it to land.
    let deadline = Date().addingTimeInterval(Tune.activateTimeout)
    while !prev.isActive && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.005)
    }
}

// MARK: - CLI

var args = Array(CommandLine.arguments.dropFirst())
while let first = args.first, first.hasPrefix("--") {
    switch first {
    case "--no-restore": restoreState = false
    case "--no-idle-wait": idleWaitEnabled = false
    default: die("unknown flag: \(first)")
    }
    args.removeFirst()
}
guard let verb = args.first else {
    die("usage: input [--no-restore] [--no-idle-wait] <verb> ... (see header)")
}
args.removeFirst()

// keyfor is a pure keyboard-layout query - it never touches the phone, so it
// must not require iPhone Mirroring to be open (unlike every other verb).
if verb == "keyfor" {
    guard let charStr = args.first, charStr.count == 1, let ch = charStr.first else {
        die("keyfor: needs exactly one character")
    }
    guard let stroke = buildKeyMap()[ch] else {
        die("keyfor: '\(ch)' is not producible on the active keyboard layout")
    }
    print("\(stroke.code) \(stroke.flags.rawValue)")
    exit(0)
}

// Window info is resolved lazily and can be refreshed: the one-shot CLI path
// resolves once, while the daemon re-resolves per command so a moved window
// never receives taps at stale coordinates.
var winCache: WindowInfo?
func currentWin() -> WindowInfo {
    if let w = winCache { return w }
    let w = resolveWindow()
    winCache = w
    return w
}

if verb == "serve" {
    runServe()   // never returns
}
if verb == "send" {
    exit(runSend(args))
}

if verb == "bounds" {
    print(currentWin().json)
    exit(0)
}

/// Content point -> absolute screen point, with bounds validation.
func toScreen(_ x: Double, _ y: Double) -> CGPoint {
    let win = currentWin()
    guard x >= 0, x < Double(win.contentWidth), y >= 0, y < Double(win.contentHeight) else {
        die("Coordinates (\(Int(x)), \(Int(y))) out of bounds (\(win.contentWidth)x\(win.contentHeight))")
    }
    return CGPoint(x: Double(win.contentX) + x, y: Double(win.contentY) + y)
}

/// One parsed, fully validated action. Parsing every action up front means a bad
/// argument anywhere fails as a clean no-op instead of stranding a half-finished
/// gesture with the mouse button held down.
struct Action {
    let verb: String
    let a: CGPoint
    let b: CGPoint
    let via: CGPoint?
    let n: [Double]
    let text: String
}

func parseAction(_ verb: String, _ f: [String]) -> Action {
    // Every numeric argument is range-checked here. Double -> integer conversions
    // in the gesture code TRAP on NaN, infinity or out-of-range values, and that
    // trap would fire mid-session with the mouse button held down.
    func num(_ i: Int, _ name: String, min lo: Double, max hi: Double) -> Double {
        guard i < f.count, let v = Double(f[i]) else { die("\(verb): missing or bad \(name)") }
        guard v.isFinite, v >= lo, v <= hi else {
            die("\(verb): \(name) must be between \(Int(lo)) and \(Int(hi)), got \(f[i])")
        }
        return v
    }
    func optNum(_ i: Int, _ fallback: Double, _ name: String, min lo: Double, max hi: Double) -> Double {
        guard i < f.count else { return fallback }
        return num(i, name, min: lo, max: hi)
    }
    // Coordinates are bounds-checked again by toScreen; this range only keeps the
    // value finite and inside Int territory before it gets there.
    let coordMax = 100_000.0
    func coord(_ i: Int, _ name: String) -> Double { num(i, name, min: -coordMax, max: coordMax) }

    let pointVerbs = ["tap", "doubletap", "longpress", "scroll", "swipe", "drag"]
    let twoPointVerbs = ["swipe", "drag"]
    let a = pointVerbs.contains(verb) ? toScreen(coord(0, "x"), coord(1, "y")) : .zero
    let b = twoPointVerbs.contains(verb) ? toScreen(coord(2, "x2"), coord(3, "y2")) : .zero
    let via = (verb == "drag" && f.count > 6) ? toScreen(coord(5, "viaX"), coord(6, "viaY")) : nil
    let durMax = 60_000.0

    switch verb {
    case "tap", "doubletap":
        return Action(verb: verb, a: a, b: b, via: via, n: [], text: "")
    case "longpress":
        return Action(verb: verb, a: a, b: b, via: via,
                      n: [optNum(2, 800, "holdMs", min: 0, max: durMax)], text: "")
    case "scroll":
        return Action(verb: verb, a: a, b: b, via: via,
                      n: [num(2, "dy", min: -coordMax, max: coordMax)], text: "")
    case "swipe", "drag":
        return Action(verb: verb, a: a, b: b, via: via,
                      n: [optNum(4, 300, "durationMs", min: 1, max: durMax)], text: "")
    case "key":
        // CGKeyCode is UInt16 but macOS virtual keycodes stop at 127; flags is a
        // UInt64 mask. Both conversions trap outside these ranges.
        return Action(verb: verb, a: a, b: b, via: via,
                      n: [num(0, "keycode", min: 0, max: 127),
                          optNum(1, 0, "flags", min: 0, max: 4_294_967_295)], text: "")
    case "sleep":
        return Action(verb: verb, a: a, b: b, via: via,
                      n: [num(0, "seconds", min: 0, max: 300)], text: "")
    case "text":
        // Validate the file BEFORE any session opens, so an unreadable path is a
        // clean no-op rather than an exit with focus and cursor still stolen.
        guard let path = f.first else { die("text: needs a utf8 file path") }
        guard (try? String(contentsOfFile: path, encoding: .utf8)) != nil else {
            die("text: cannot read utf8 file: \(path)")
        }
        return Action(verb: verb, a: a, b: b, via: via, n: [], text: path)
    default:
        die("unknown verb: \(verb)")
    }
}

func run(_ act: Action) {
    switch act.verb {
    case "tap":       doTap(act.a)
    case "doubletap": doDoubleTap(act.a)
    case "longpress": doLongPress(act.a, holdMs: act.n[0])
    case "scroll":    doScroll(act.a, dy: act.n[0])
    case "swipe":     doSwipe(act.a, act.b, durationMs: act.n[0])
    case "drag":      doDrag(act.a, act.b, hoverMs: act.n[0], via: act.via)
    case "key":       postKey(CGKeyCode(act.n[0]), flags: CGEventFlags(rawValue: UInt64(act.n[1])))
    case "sleep":     Thread.sleep(forTimeInterval: act.n[0])
    case "text":      doText(act.text)
    default:          die("unknown verb: \(act.verb)")
    }
}

// batch: one action per stdin line, all inside ONE session. A sequence costs one
// process launch and one focus steal instead of N of each.
var actions: [Action] = []
if verb == "batch" {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        var fields = trimmed.split(separator: " ").map(String.init)
        let v = fields.removeFirst()
        actions.append(parseAction(v, fields))
    }
    if actions.isEmpty { die("batch: no actions on stdin") }
} else {
    actions = [parseAction(verb, args)]
}

let session = beginSession()
lastPoint = session.cursor
for act in actions { run(act) }
endSession(session)
