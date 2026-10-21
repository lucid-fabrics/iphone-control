// Window resolution for the native input engine.
//
// The fast path is pure CoreGraphics: list windows, then reuse cached content
// bounds if they describe this exact frame. On a miss we shell out to
// find-window.sh, which owns the alpha-scan logic - one implementation of the
// tricky part, and it runs at most once per cache TTL (or when the window moves).

import AppKit
import CoreGraphics
import Foundation

struct WindowFrame {
    var id: CGWindowID
    var x: Int, y: Int, width: Int, height: Int
}

struct WindowInfo {
    var windowID: CGWindowID
    var x: Int, y: Int, width: Int, height: Int
    var contentX: Int, contentY: Int, contentWidth: Int, contentHeight: Int
    var scale: Int

    var json: String {
        "{\"x\":\(x),\"y\":\(y),\"width\":\(width),\"height\":\(height)," +
        "\"content_x\":\(contentX),\"content_y\":\(contentY)," +
        "\"content_width\":\(contentWidth),\"content_height\":\(contentHeight)," +
        "\"window_id\":\(windowID),\"scale\":\(scale)}"
    }
}

/// True when a CGWindowList entry belongs to iPhone Mirroring. Matches the owner's
/// bundle ID, never kCGWindowOwnerName, which is localized (e.g. Japanese macOS).
func isMirroringWindow(_ info: [String: Any]) -> Bool {
    guard let pid = info[kCGWindowOwnerPID as String] as? Int else { return false }
    return NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier == Tune.bundleID
}

/// Frame of the mirroring window in global points, or nil if it is not open.
func mirroringWindowFrame() -> WindowFrame? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    for win in list {
        guard isMirroringWindow(win),
              let num = win[kCGWindowNumber as String] as? Int,
              let b = win[kCGWindowBounds as String] as? [String: CGFloat]
        else { continue }
        let w = Int((b["Width"] ?? 0).rounded()), h = Int((b["Height"] ?? 0).rounded())
        guard w > 100, h > 100 else { continue }
        return WindowFrame(id: CGWindowID(num), x: Int((b["X"] ?? 0).rounded()),
                           y: Int((b["Y"] ?? 0).rounded()), width: w, height: h)
    }
    return nil
}

func parseIntField(_ json: String, _ field: String) -> Int? {
    guard let r = json.range(of: "\"\(field)\":") else { return nil }
    return Int(json[r.upperBound...].prefix(while: { $0.isNumber || $0 == "-" }))
}

private func infoFromJSON(_ json: String, _ f: WindowFrame) -> WindowInfo? {
    guard let cx = parseIntField(json, "content_x"), let cy = parseIntField(json, "content_y"),
          let cw = parseIntField(json, "content_width"), let ch = parseIntField(json, "content_height"),
          let sc = parseIntField(json, "scale"), cw > 0, ch > 0
    else { return nil }
    return WindowInfo(windowID: f.id, x: f.x, y: f.y, width: f.width, height: f.height,
                      contentX: cx, contentY: cy, contentWidth: cw, contentHeight: ch, scale: sc)
}

/// Cached content bounds, but only if the cache is fresh AND describes this
/// exact window id/position/size (it goes stale when the window moves).
private func cachedInfo(for f: WindowFrame) -> WindowInfo? {
    guard let cached = try? String(contentsOfFile: Tune.cachePath, encoding: .utf8),
          let key = try? String(contentsOfFile: Tune.cacheKeyPath, encoding: .utf8),
          let attrs = try? FileManager.default.attributesOfItem(atPath: Tune.cachePath),
          let mtime = attrs[.modificationDate] as? Date,
          Date().timeIntervalSince(mtime) < Tune.cacheTTL
    else { return nil }

    let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|").map(String.init)
    guard parts.count == 6, parts[0] == String(f.id), parts[1] == String(f.x),
          parts[2] == String(f.y), parts[3] == String(f.width), parts[4] == String(f.height)
    else { return nil }
    return infoFromJSON(cached, f)
}

/// Fresh scan via find-window.sh (two levels up from this binary: helpers/input).
private func scanViaShell(_ f: WindowFrame) -> WindowInfo? {
    let helperDir = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath().deletingLastPathComponent()
    let script = helperDir.deletingLastPathComponent().appendingPathComponent("find-window.sh")
    guard FileManager.default.isExecutableFile(atPath: script.path) else { return nil }

    let proc = Process()
    proc.executableURL = script
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do { try proc.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0, let json = String(data: data, encoding: .utf8) else { return nil }
    return infoFromJSON(json, f)
}

func resolveWindow() throws -> WindowInfo {
    guard let f = mirroringWindowFrame() else {
        throw CommandError(message: "iPhone Mirroring window not found. Is iPhone Mirroring open?")
    }
    if let hit = cachedInfo(for: f) { return hit }
    guard let info = scanViaShell(f) else {
        throw CommandError(message: "Failed to detect content bounds. Check Screen Recording permission.")
    }
    return info
}
