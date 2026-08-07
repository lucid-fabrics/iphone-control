// Event posting and gesture recipes for the native input engine.
//
// Each recipe encodes a hard-won constraint of iPhone Mirroring; see the
// comments on individual functions before changing any timing.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Event posting

let eventSource = CGEventSource(stateID: .hidSystemState)
var lastPoint = CGPoint.zero

/// Post a mouse event with full hardware fidelity: per-event deltas, click state
/// and pressure. SpringBoard's drag recognizer rejects streams lacking these.
func postMouse(_ type: CGEventType, _ p: CGPoint, pressure: Double, clickState: Int64 = 1) {
    guard let e = CGEvent(mouseEventSource: eventSource, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: clickState)
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64((p.x - lastPoint.x).rounded()))
    e.setIntegerValueField(.mouseEventDeltaY, value: Int64((p.y - lastPoint.y).rounded()))
    e.setDoubleValueField(.mouseEventPressure, value: pressure)
    e.post(tap: .cghidEventTap)
    lastPoint = p
}

func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
    guard let dn = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false)
    else { return }
    dn.flags = flags
    up.flags = flags
    dn.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: Tune.keyDelay)
    up.post(tap: .cghidEventTap)
}

// MARK: - Gestures

func doTap(_ p: CGPoint) {
    postMouse(.leftMouseDown, p, pressure: 1.0)
    Thread.sleep(forTimeInterval: Tune.tapDelay)
    postMouse(.leftMouseUp, p, pressure: 0.0)
}

func doDoubleTap(_ p: CGPoint) {
    postMouse(.mouseMoved, p, pressure: 0.0, clickState: 0)
    for state in Int64(1)...Int64(2) {
        postMouse(.leftMouseDown, p, pressure: 1.0, clickState: state)
        Thread.sleep(forTimeInterval: Tune.tapDelay)
        postMouse(.leftMouseUp, p, pressure: 0.0, clickState: state)
        if state == 1 { Thread.sleep(forTimeInterval: 0.06) }
    }
}

func doLongPress(_ p: CGPoint, holdMs: Double) {
    postMouse(.mouseMoved, p, pressure: 0.0, clickState: 0)
    Thread.sleep(forTimeInterval: 0.05)
    postMouse(.leftMouseDown, p, pressure: 1.0)
    Thread.sleep(forTimeInterval: holdMs / 1000.0)
    postMouse(.leftMouseUp, p, pressure: 0.0)
}

func doSwipe(_ a: CGPoint, _ b: CGPoint, durationMs: Double) {
    let steps = Tune.swipeSteps
    let stepDelay = durationMs / 1000.0 / Double(steps)
    let dx = b.x - a.x, dy = b.y - a.y
    postMouse(.leftMouseDown, a, pressure: 1.0)
    // Immediate kick: iOS classifies drag vs long-press within ~50ms, so the
    // pointer must clear the slop threshold before that window closes.
    let k = Tune.swipeKickFactor
    postMouse(.leftMouseDragged, CGPoint(x: a.x + dx * k, y: a.y + dy * k), pressure: 1.0)
    for i in 1...steps {
        Thread.sleep(forTimeInterval: stepDelay)
        let f = k + (1.0 - k) * (Double(i) / Double(steps))
        postMouse(.leftMouseDragged, CGPoint(x: a.x + dx * f, y: a.y + dy * f), pressure: 1.0)
    }
    postMouse(.leftMouseUp, b, pressure: 0.0)
}

/// Mirroring only honors LINE-unit wheel events; pixel-unit events and drag
/// gestures do not scroll iOS lists.
func doScroll(_ p: CGPoint, dy: Double) {
    postMouse(.mouseMoved, p, pressure: 0.0, clickState: 0)
    Thread.sleep(forTimeInterval: 0.1)
    let lines = max(1, Int((abs(dy) / Tune.scrollPointsPerLine).rounded()))
    let dir: Int32 = dy > 0 ? -1 : 1
    let events = Int((Double(lines) / Double(Tune.scrollLinesPerEvent)).rounded(.up))
    for _ in 0..<events {
        guard let e = CGEvent(scrollWheelEvent2Source: eventSource, units: .line, wheelCount: 1,
                              wheel1: dir * Tune.scrollLinesPerEvent, wheel2: 0, wheel3: 0)
        else { continue }
        e.location = p
        e.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.03)
    }
}

/// Median normalized displacement-vs-time curve extracted from 7 recorded HUMAN
/// icon drags (see helpers/event-logger.swift): gentle start, a ~2.3x velocity
/// burst around 30-40% of the movement, then a long tapering landing where the
/// final 15% of time covers almost no distance. SpringBoard tracks this shape
/// far more reliably than a symmetric ease. Keep in sync with the JS copy in
/// helpers/common.sh jxa_icon_drag_body.
let humanDragCurve: [Double] = [
    0.0, 0.031, 0.072, 0.108, 0.163, 0.22, 0.326, 0.441, 0.558, 0.64,
    0.683, 0.756, 0.801, 0.831, 0.889, 0.931, 0.983, 0.985, 0.994, 1.0, 1.0
]

func humanCurveAt(_ t: Double) -> Double {
    let clamped = max(0.0, min(1.0, t))
    let x = clamped * Double(humanDragCurve.count - 1)
    let i = min(humanDragCurve.count - 2, Int(x))
    let frac = x - Double(i)
    return humanDragCurve[i] + (humanDragCurve[i + 1] - humanDragCurve[i]) * frac
}

/// Human-like drag segment: ~125Hz, subpixel positions, the measured human
/// velocity curve, and a curved path. Humans do not move in straight lines -
/// measured mean deviation was 3.3px, mostly a single bow, so the path arcs
/// (deterministically, alternating side by origin parity) with light noise on
/// top. A robotic straight-line drag is not tracked by SpringBoard.
func dragSegment(_ a: CGPoint, _ b: CGPoint) {
    let dx = b.x - a.x, dy = b.y - a.y
    let dist = max(1.0, (dx * dx + dy * dy).squareRoot())
    let n = max(1, Int((max(300.0, dist / Tune.iconDragSpeed) / Tune.iconDragStepMs).rounded()))
    let bowSide: Double = (Int(a.x + a.y) % 2 == 0) ? 1 : -1
    let bowAmp = min(5.0, dist * 0.03) * bowSide
    for i in 1...n {
        Thread.sleep(forTimeInterval: Tune.iconDragStepMs / 1000.0)
        let t = Double(i) / Double(n)
        let f = humanCurveAt(t)
        let bow = sin(t * .pi) * bowAmp
        let noise = ((Double(i) * 0.37).truncatingRemainder(dividingBy: 1) - 0.5) * 0.6
        let off = bow + noise
        postMouse(.leftMouseDragged,
                  CGPoint(x: a.x + dx * f + (-dy / dist) * off,
                          y: a.y + dy * f + (dx / dist) * off),
                  pressure: 1.0)
    }
}

/// Keep-alive wiggle: a drag session that goes silent for ~2s is cancelled by
/// iOS and the item snaps back to its origin.
func dragHover(_ p: CGPoint, seconds: Double) {
    let n = Int((seconds / 0.05).rounded())
    guard n > 0 else { return }
    for i in 0..<n {
        Thread.sleep(forTimeInterval: 0.05)
        postMouse(.leftMouseDragged,
                  CGPoint(x: p.x + sin(Double(i) * 0.9) * 0.4, y: p.y + cos(Double(i) * 0.7) * 0.4),
                  pressure: 1.0)
    }
}

func doDrag(_ a: CGPoint, _ b: CGPoint, hoverMs: Double, via: CGPoint?) {
    postMouse(.mouseMoved, a, pressure: 0.0, clickState: 0)
    Thread.sleep(forTimeInterval: 0.1)
    postMouse(.leftMouseDown, a, pressure: 1.0)
    Thread.sleep(forTimeInterval: Tune.iconDragLiftHold)
    if let v = via {
        dragSegment(a, v)
        dragHover(v, seconds: 0.7)
        dragSegment(v, b)
    } else {
        dragSegment(a, b)
    }
    dragHover(b, seconds: hoverMs / 1000.0)
    // Land still on the exact drop point before releasing, like a human settling
    // before letting go (measured ~135ms). Gives SpringBoard a stationary target
    // to commit the drop to, which is where reordering placement was slipping.
    postMouse(.leftMouseDragged, b, pressure: 1.0)
    Thread.sleep(forTimeInterval: Tune.iconDragLandingSettle)
    postMouse(.leftMouseUp, b, pressure: 0.0)
}

/// Type text as real key presses. Mirroring forwards virtual keycodes and
/// ignores unicode payloads, so every character is resolved to the key that
/// produces it on the active layout. Characters with no such key (emoji,
/// non-layout scripts) are reported rather than silently typed as garbage.
func doText(_ path: String) {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else {
        die("text: needs a readable utf8 file path")
    }
    let map = buildKeyMap()
    var unsupported: [Character] = []
    for ch in s {
        guard let stroke = map[ch] else {
            unsupported.append(ch)
            continue
        }
        postKey(stroke.code, flags: stroke.flags)
        Thread.sleep(forTimeInterval: 0.008)
    }
    if !unsupported.isEmpty {
        let list = String(unsupported.prefix(10))
        fputs("Warning: \(unsupported.count) character(s) not on the current " +
              "keyboard layout were skipped: \(list)\n", stderr)
    }
}
