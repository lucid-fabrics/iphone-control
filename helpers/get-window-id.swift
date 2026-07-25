import CoreGraphics
import Foundation

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    fputs("error: cannot list windows\n", stderr)
    exit(1)
}

for win in list {
    guard let owner = win["kCGWindowOwnerName"] as? String, owner == "iPhone Mirroring" else { continue }
    let num = win["kCGWindowNumber"] as? Int ?? 0
    let bounds = win["kCGWindowBounds"] as? [String: Any] ?? [:]
    let winX = bounds["X"] as? CGFloat ?? 0
    let winY = bounds["Y"] as? CGFloat ?? 0
    let winWidth = bounds["Width"] as? CGFloat ?? 0
    let winHeight = bounds["Height"] as? CGFloat ?? 0
    // Global top-left coordinates; negative on displays left of / above the primary.
    // Rounded to integers: bash arithmetic downstream cannot handle fractional origins.
    // Scale is NOT detected here: find-window.sh measures it from the actual capture,
    // which is correct even for windows straddling displays or gapped arrangements.
    print("\(num)|\(Int(winX.rounded()))|\(Int(winY.rounded()))|\(Int(winWidth.rounded()))|\(Int(winHeight.rounded()))")
    exit(0)
}

fputs("error: iPhone Mirroring window not found\n", stderr)
exit(1)
