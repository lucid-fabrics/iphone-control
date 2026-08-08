import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

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
        // Request 2x; the crop below measures the ACTUAL delivered scale from the
        // image itself, so any real scale stays correct (mixed-DPI safe).
        config.width = Int(geo.window.width) * 2
        config.height = Int(geo.window.height) * 2
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
