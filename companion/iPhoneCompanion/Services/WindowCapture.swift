import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import Vision

/// One-shot in-process ScreenCaptureKit capture of the iPhone Mirroring window,
/// cropped to the iOS content rect and resampled to point dimensions (1 image
/// pixel == 1 tap point). Ported from helpers/input-src/capture.swift. SCK reads
/// the window straight from the window server, so the mirror's activation state
/// and window occlusion cannot black the frame the way screencapture could.
enum WindowCapture {
    struct Geometry {
        let windowID: CGWindowID
        let window: CGRect      // screen points
        let content: CGRect     // screen points
    }

    /// Locate the mirroring window and pair it with the given (alpha-scanned)
    /// content bounds. Returns nil when the mirror is not on screen.
    static func geometry(contentBounds: InputController.ContentBounds) -> Geometry? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in list {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "iPhone Mirroring",
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
            else { continue }
            var rect = CGRect.zero
            CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect)
            guard rect.width > 100, rect.height > 100 else { continue }
            let content = CGRect(
                x: CGFloat(contentBounds.contentX), y: CGFloat(contentBounds.contentY),
                width: CGFloat(contentBounds.contentWidth), height: CGFloat(contentBounds.contentHeight)
            )
            return Geometry(windowID: windowID, window: rect, content: content)
        }
        return nil
    }

    /// Capture the window via SCK, crop to content, resample to points, encode PNG.
    static func capturePNG(_ geo: Geometry) async -> Data? {
        guard let shareable = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let scWindow = shareable.windows.first(where: { $0.windowID == geo.windowID })
        else { return nil }

        let config = SCStreamConfiguration()
        // Canvas must be the window's REAL backing size (points x that display's
        // scale). A hardcoded 2x on a Retina display made SCK allocate a 4x-pixel
        // canvas and draw the window unscaled in the top-left corner, so captures
        // came out quarter-content with black padding.
        let backingScale = displayScale(for: geo.window)
        config.width = Int(geo.window.width * backingScale)
        config.height = Int(geo.window.height * backingScale)
        config.showsCursor = false
        config.captureResolution = .best

        guard let raw = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
            configuration: config
        ) else { return nil }

        let scale = Double(raw.width) / Double(geo.window.width)
        let cropRect = CGRect(
            x: (geo.content.minX - geo.window.minX) * scale,
            y: (geo.content.minY - geo.window.minY) * scale,
            width: geo.content.width * scale,
            height: geo.content.height * scale
        ).integral
        // Keep NATIVE pixels (720x1560 on a Retina display) instead of resampling
        // down to points: tap coordinates are normalized 0-1000 so image size never
        // affects them, and small UI text at 360px was too coarse for model vision.
        guard let cropped = raw.cropping(to: cropRect) else { return nil }
        return pngData(cropped)
    }

    /// Backing scale of the display containing the window. CGWindow bounds are
    /// top-left global coords; NSScreen frames are bottom-left, so flip via the
    /// PRIMARY screen's height before intersecting (same as the dock math).
    private static func displayScale(for windowRect: CGRect) -> CGFloat {
        guard let primary = NSScreen.screens.first else { return 2 }
        let appKitRect = NSRect(
            x: windowRect.minX,
            y: primary.frame.height - windowRect.minY - windowRect.height,
            width: windowRect.width, height: windowRect.height
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitRect) }
        return screen?.backingScaleFactor ?? 2
    }

    /// Debug: save the screen with a red marker at a 0-1000 grid point, so a tap's
    /// real landing spot can be inspected on disk instead of inferred from what the
    /// model claims. Files land in /tmp/iphone-companion-taps/.
    @discardableResult
    static func writeTapMarker(normX: Int, normY: Int, png: Data, note: String,
                               sidecar: String? = nil) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = img.width, height = img.height
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext is bottom-left origin; the grid is top-down.
        let posX = Double(normX) / 1000.0 * Double(width)
        let posY = Double(height) - Double(normY) / 1000.0 * Double(height)
        let radius = Double(min(width, height)) / 26.0
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(max(2, radius / 5))
        ctx.strokeEllipse(in: CGRect(x: posX - radius, y: posY - radius,
                                     width: radius * 2, height: radius * 2))
        ctx.move(to: CGPoint(x: posX - radius * 1.8, y: posY))
        ctx.addLine(to: CGPoint(x: posX + radius * 1.8, y: posY))
        ctx.move(to: CGPoint(x: posX, y: posY - radius * 1.8))
        ctx.addLine(to: CGPoint(x: posX, y: posY + radius * 1.8))
        ctx.strokePath()

        guard let marked = ctx.makeImage(), let out = pngData(marked) else { return nil }
        let dir = "/tmp/iphone-companion-taps"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let safeNote = note.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_").prefix(40)
        try? out.write(to: URL(fileURLWithPath: "\(dir)/\(stamp)-\(safeNote).png"))
        if let sidecar, !sidecar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? sidecar.write(toFile: "\(dir)/\(stamp)-\(safeNote).txt",
                               atomically: true, encoding: .utf8)
        }
        return out
    }

    /// Button-like shapes (circles, rounded rects) on the screen, as 0-1000 grid
    /// centers. Complements OCR: Vision's text pass never emits unlabeled controls
    /// (the Calculator's multiply/divide keys, download clouds, chevrons), which
    /// forced models to estimate positions - the source of every remaining miss.
    static func detectButtons(png: Data) -> [(x: Int, y: Int)] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }

        var centers: [(x: Int, y: Int)] = []
        // Two passes: light controls on dark UI and dark controls on light UI.
        for darkOnLight in [false, true] {
            let request = VNDetectContoursRequest()
            request.contrastAdjustment = 1.5
            request.detectsDarkOnLight = darkOnLight
            request.maximumImageDimension = 1024
            let handler = VNImageRequestHandler(cgImage: img)
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first else { continue }

            var candidates: [VNContour] = []
            for top in observation.topLevelContours {
                candidates.append(top)
                // A huge top-level contour is usually the screen border wrapping
                // everything; its children are the actual controls.
                if top.normalizedPath.boundingBox.width > 0.6 {
                    candidates.append(contentsOf: top.childContours)
                }
            }
            for contour in candidates {
                let box = contour.normalizedPath.boundingBox
                let gridW = box.width * 1000
                let gridH = box.height * 1000
                // Button-sized only: a Calculator key is ~215 grid units wide, a
                // download cloud ~85, a chevron ~55.
                guard gridW > 40, gridW < 320, gridH > 40, gridH < 320,
                      gridW / max(gridH, 1) < 3, gridH / max(gridW, 1) < 3
                else { continue }
                let center = (x: Int(box.midX * 1000), y: Int((1 - box.midY) * 1000))
                // Dedupe near-identical shapes across the two passes.
                if centers.contains(where: { abs($0.x - center.x) < 50 && abs($0.y - center.y) < 50 }) {
                    continue
                }
                centers.append(center)
                if centers.count >= 30 { return centers }
            }
        }
        return centers
    }

    private static func pngData(_ img: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
