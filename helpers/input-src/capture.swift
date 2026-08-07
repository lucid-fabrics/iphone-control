// Native window capture for the daemon.
//
// One-shot ScreenCaptureKit capture (~30-50ms) with a `screencapture` process
// fallback (~150ms) if SCK is unavailable or errors. All outputs are cropped to
// the iOS CONTENT rect, so downstream consumers never see window chrome.

import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

/// Capture the mirroring window at native pixel scale. Returns nil on failure.
func captureWindowImage(_ win: WindowInfo) -> CGImage? {
    if let img = captureViaSCK(win) { return img }
    return captureViaSpawn(win)
}

private func captureViaSCK(_ win: WindowInfo) -> CGImage? {
    var content: SCShareableContent?
    let contentSem = DispatchSemaphore(value: 0)
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { got, _ in
        content = got
        contentSem.signal()
    }
    guard contentSem.wait(timeout: .now() + 2) == .success,
          let scWindow = content?.windows.first(where: { $0.windowID == win.windowID })
    else { return nil }

    let config = SCStreamConfiguration()
    config.width = win.width * win.scale
    config.height = win.height * win.scale
    config.showsCursor = false
    config.captureResolution = .best

    var image: CGImage?
    let shotSem = DispatchSemaphore(value: 0)
    SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
        configuration: config
    ) { img, _ in
        image = img
        shotSem.signal()
    }
    guard shotSem.wait(timeout: .now() + 2) == .success else { return nil }
    return image
}

private func captureViaSpawn(_ win: WindowInfo) -> CGImage? {
    let tmp = "/tmp/input-capture-\(getpid()).png"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", "-l", String(win.windowID), "-o", tmp]
    proc.standardError = FileHandle.nullDevice
    do { try proc.run() } catch { return nil }
    proc.waitUntilExit()
    guard proc.terminationStatus == 0,
          let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Crop a native window capture to the iOS content rect (native pixels).
/// The capture's actual pixel scale is measured from the image itself, the same
/// trick find-window.sh uses, so mixed-DPI display arrangements stay correct.
func cropToContent(_ img: CGImage, _ win: WindowInfo) -> CGImage? {
    let scale = Double(img.width) / Double(win.width)
    let rect = CGRect(
        x: Double(win.contentX - win.x) * scale,
        y: Double(win.contentY - win.y) * scale,
        width: Double(win.contentWidth) * scale,
        height: Double(win.contentHeight) * scale
    )
    return img.cropping(to: rect.integral)
}

/// Resample to exact point dimensions (the normalized coordinate space every
/// other command uses: 1 image pixel == 1 tap point).
func resampleToPoints(_ img: CGImage, _ win: WindowInfo) -> CGImage? {
    let w = win.contentWidth, h = win.contentHeight
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

func writePNG(_ img: CGImage, to path: String) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
    ) else { return false }
    CGImageDestinationAddImage(dest, img, nil)
    return CGImageDestinationFinalize(dest)
}

/// Tiny grayscale frame for stillness comparison. Mirroring is a live video
/// stream (frames are never byte-identical), but at 32px the codec noise
/// collapses to ~0, so a small mean-abs-diff tolerance separates "settled"
/// from "animating".
func stillnessFrame(_ win: WindowInfo) -> [UInt8]? {
    guard let raw = captureWindowImage(win), let img = cropToContent(raw, win) else { return nil }
    let w = Tune.stillSize
    let h = max(1, img.height * w / max(1, img.width))
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .low
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h))
}

func framesMatch(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    let n = min(a.count, b.count)
    guard n > 0 else { return false }
    var total = 0
    for i in 0..<n { total += abs(Int(a[i]) - Int(b[i])) }
    return Double(total) / Double(n) <= Tune.stillTolerance
}
