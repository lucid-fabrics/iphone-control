import AppKit
import CoreGraphics
import Foundation

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    fputs("error: cannot list windows\n", stderr)
    exit(1)
}

// Resolve the Mirroring PID(s) once; matching by bundle ID because
// kCGWindowOwnerName is localized (for example, `iPhoneミラーリング`
// with Japanese as the macOS display language).
let mirroringPIDs = Set(
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity")
        .map { Int($0.processIdentifier) }
)

for win in list {
    guard let ownerPID = win["kCGWindowOwnerPID"] as? Int, mirroringPIDs.contains(ownerPID) else { continue }
    let num = win["kCGWindowNumber"] as? Int ?? 0
    let bounds = win["kCGWindowBounds"] as? [String: Any] ?? [:]
    let winX = bounds["X"] as? CGFloat ?? 0
    let winY = bounds["Y"] as? CGFloat ?? 0
    let winWidth = bounds["Width"] as? CGFloat ?? 0
    let winHeight = bounds["Height"] as? CGFloat ?? 0
    // Skip tiny helper windows (menu bar extras, shadows), same filter as the other sites.
    guard winWidth > 100, winHeight > 100 else { continue }
    // Global top-left coordinates; negative on displays left of / above the primary.
    // Rounded to integers: bash arithmetic downstream cannot handle fractional origins.
    // Scale is NOT detected here: find-window.sh measures it from the actual capture,
    // which is correct even for windows straddling displays or gapped arrangements.
    print("\(num)|\(Int(winX.rounded()))|\(Int(winY.rounded()))|\(Int(winWidth.rounded()))|\(Int(winHeight.rounded()))")
    exit(0)
}

fputs("error: iPhone Mirroring window not found\n", stderr)
exit(1)
