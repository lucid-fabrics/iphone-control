import Foundation
import CoreGraphics
import AppKit

struct ToolResult {
    let text: String?
    let imageData: Data?
    let isError: Bool

    static func text(_ text: String) -> ToolResult {
        ToolResult(text: text, imageData: nil, isError: false)
    }

    static func image(_ data: Data) -> ToolResult {
        ToolResult(text: nil, imageData: data, isError: false)
    }

    static func error(_ message: String) -> ToolResult {
        ToolResult(text: message, imageData: nil, isError: true)
    }
}

// One method per tool keeps the dispatch flat and readable; splitting the actor
// would scatter closely-related device actions across files.
// swiftlint:disable type_body_length
actor ToolExecutor {
    let scriptRunner: ScriptRunning
    let inputController: InputControlling

    init(scriptsPath: String = Constants.defaultScriptsPath) {
        let runner = ScriptRunner(scriptsPath: scriptsPath)
        self.scriptRunner = runner
        self.inputController = InputController(scriptRunner: runner)
    }

    init(scriptRunner: ScriptRunning, inputController: InputControlling) {
        self.scriptRunner = scriptRunner
        self.inputController = inputController
    }

    // Flat tool-name dispatch; one case per tool is clearer than any indirection.
    // swiftlint:disable:next cyclomatic_complexity
    func execute(toolName: String, input: [String: Any]) async -> ToolResult {
        do {
            switch toolName {
            case "find_window":
                return try await executeFindWindow()
            case "screenshot":
                return try await executeScreenshot()
            case "tap":
                return try await executeTap(input: input)
            case "tap_text":
                return try await executeTapText(input: input)
            case "swipe":
                return try await executeSwipe(input: input)
            case "type_text":
                return try await executeTypeText(input: input)
            case "press_key":
                return try await executePressKey(input: input)
            case "open_app":
                return try await executeOpenApp(input: input)
            case "home":
                return try await executeHome()
            case "app_switcher":
                return try await executeAppSwitcher()
            case "status":
                return try await executeStatus()
            case "scan_apps", "map_apps":
                return try await executeScanApps(input: input)
            case "list_apps":
                return try await executeListApps()
            default:
                return .error("Unknown tool: \(toolName)")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Individual Tool Methods

    private func executeFindWindow() async throws -> ToolResult {
        // Script first: alpha-scanned bounds, not the native rough-margin estimate.
        if let result = try? await scriptRunner.run(script: "find-window.sh"),
           !result.stdout.isEmpty {
            return .text(result.stdout)
        }
        if let result = nativeFindWindow() { return result }
        throw InputError.windowNotFound
    }

    private func executeScreenshot() async throws -> ToolResult {
        // Primary: in-process ScreenCaptureKit. Reads the window straight from the
        // window server (activation/occlusion can't black it) and crops to the
        // alpha-scanned content rect, so pixels map 1:1 onto tap points.
        if let bounds = try? await inputController.getContentBounds(),
           let geo = WindowCapture.geometry(contentBounds: bounds),
           let png = await WindowCapture.capturePNG(geo),
           !isMostlyBlackFrame(png) {
            return .image(png)
        }

        // Fallbacks: screenshot.sh (same crop via scripts), then rough native crop.
        let capture = (try? await scriptScreenshot()) ?? nativeScreenshot()
        guard let result = capture else {
            return .error("Screenshot failed. Check Screen Recording permission.")
        }

        // Mirroring intermittently yields all-black window captures depending on
        // its activation state (observed both ways tonight; CLI captures with the
        // mirror in the BACKGROUND always worked, and the one in-app success came
        // right after an action that shuffled activation). A black frame fed to
        // the model triggers hallucinations, so walk a retry ladder that tries
        // BOTH activation states and never forward a black frame.
        guard let data = result.imageData, isMostlyBlackFrame(data) else { return result }

        // Attempt 1: send the mirror to the background (matches the always-working
        // CLI condition) and retake.
        await setMirroringActive(false)
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let retaken = (try? await scriptScreenshot()) ?? nativeScreenshot(),
           let newData = retaken.imageData, !isMostlyBlackFrame(newData) {
            return retaken
        }

        // Attempt 2: foreground the mirror (wakes a paused stream) and retake.
        await setMirroringActive(true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if let retaken = (try? await scriptScreenshot()) ?? nativeScreenshot(),
           let newData = retaken.imageData, !isMostlyBlackFrame(newData) {
            return retaken
        }
        // A black screen is a NORMAL state (display asleep / mirroring idle), not a
        // failure. Reporting it as an error made models panic and spiral into
        // "the window is off-screen / the session is broken" recovery attempts.
        return .text("The iPhone screen is currently black (display asleep or "
            + "mirroring idle). This is normal and NOT an error. Wake it with the "
            + "home tool or a tap, then take another screenshot. Everything is "
            + "connected and working - do not try to diagnose the window or session.")
    }

    private func scriptScreenshot() async throws -> ToolResult {
        let tmpPath = "/tmp/iphone-companion-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let result = try await scriptRunner.run(script: "screenshot.sh", args: [tmpPath])
        let outputPath = result.stdout.isEmpty ? tmpPath : result.stdout
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)) else {
            throw InputError.windowNotFound
        }
        try? FileManager.default.removeItem(atPath: outputPath)
        return .image(data)
    }

    // MARK: - Native CG Implementations (no child process, no TCC inheritance issues)

    private func iphoneMirroringWindows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return list.filter { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "iPhone Mirroring",
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
            else { return false }
            var rect = CGRect.zero
            CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect)
            return rect.width > 100 && rect.height > 100
        }
    }

    private func nativeFindWindow() -> ToolResult? {
        guard let window = iphoneMirroringWindows().first,
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
        else { return nil }

        var rect = CGRect.zero
        CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect)

        let marginX = Int(rect.width * 0.06)
        let marginTop = Int(rect.height * 0.09)
        let marginBottom = Int(rect.height * 0.04)

        let fields: [String] = [
            "\"window_x\":\(Int(rect.minX))",
            "\"window_y\":\(Int(rect.minY))",
            "\"window_width\":\(Int(rect.width))",
            "\"window_height\":\(Int(rect.height))",
            "\"content_x\":\(Int(rect.minX) + marginX)",
            "\"content_y\":\(Int(rect.minY) + marginTop)",
            "\"content_width\":\(Int(rect.width) - marginX * 2)",
            "\"content_height\":\(Int(rect.height) - marginTop - marginBottom)"
        ]
        return .text("{" + fields.joined(separator: ",") + "}")
    }

    private func nativeScreenshot() -> ToolResult? {
        guard let window = iphoneMirroringWindows().first,
              let windowId = window[kCGWindowNumber as String] as? CGWindowID,
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
        else { return nil }

        var rect = CGRect.zero
        CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect)

        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionIncludingWindow,
            windowId,
            [.boundsIgnoreFraming, .shouldBeOpaque]
        ) else { return nil }

        // Crop to content area (remove bezels).
        // CGWindowListCreateImage returns PIXELS (2x on Retina) while rect is points;
        // cropping(to:) works in pixels, so scale the margins by the measured ratio.
        let pixelScale = rect.width > 0 ? CGFloat(cgImage.width) / rect.width : 1
        let marginX = Int(rect.width * 0.06 * pixelScale)
        let marginTop = Int(rect.height * 0.09 * pixelScale)
        let marginBottom = Int(rect.height * 0.04 * pixelScale)
        let cropRect = CGRect(
            x: marginX, y: marginTop,
            width: cgImage.width - marginX * 2,
            height: cgImage.height - marginTop - marginBottom
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let nsImage = NSImage(cgImage: cropped, size: cropRect.size)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return nil }

        return .image(pngData)
    }

    private func executeTap(input: [String: Any]) async throws -> ToolResult {
        guard let tapX = intValue(input["x"]),
              let tapY = intValue(input["y"]) else {
            return .error("tap requires x and y coordinates")
        }
        _ = try await inputController.tap(x: tapX, y: tapY)
        return .text("Tapped at (\(tapX), \(tapY)). Screenshot to verify.")
    }

    private func executeTapText(input: [String: Any]) async throws -> ToolResult {
        guard let text = input["text"] as? String, !text.isEmpty else {
            return .error("tap_text requires a non-empty text parameter")
        }
        var args = [text]
        if let index = numberValue(input["index"]) {
            args.append(contentsOf: ["--index", index])
        }
        do {
            let result = try await scriptRunner.run(
                script: "tap-text.sh", args: args, timeout: Constants.defaultScriptTimeout)
            return .text(result.stdout.isEmpty ? "Tapped text: \(text)" : result.stdout)
        } catch {
            // No OCR match: tell the model so it can retry different text or use tap.
            return .error("Could not find text \"\(text)\" on screen. Try different wording or use tap.")
        }
    }

    private func executeSwipe(input: [String: Any]) async throws -> ToolResult {
        guard let startX = intValue(input["x1"]),
              let startY = intValue(input["y1"]),
              let endX = intValue(input["x2"]),
              let endY = intValue(input["y2"]) else {
            return .error("swipe requires x1, y1, x2, y2 coordinates")
        }
        let duration = intValue(input["duration_ms"]) ?? Constants.defaultSwipeDuration
        _ = try await inputController.swipe(
            x1: startX, y1: startY, x2: endX, y2: endY, durationMs: duration)
        return .text("Swiped from (\(startX),\(startY)) to (\(endX),\(endY)). Screenshot to verify.")
    }

    private func executeTypeText(input: [String: Any]) async throws -> ToolResult {
        guard let text = input["text"] as? String else {
            return .error("type_text requires text parameter")
        }
        let tapX = intValue(input["x"])
        let tapY = intValue(input["y"])
        // Default to submitting: a search box that is typed into but never gets a
        // Return just sits there and no results appear (the old silent dead end).
        let submit = (input["submit"] as? Bool) ?? true
        _ = try await inputController.typeText(text, tapX: tapX, tapY: tapY, submit: submit)
        return .text("Typed: \"\(text)\"\(submit ? " and pressed Return" : ""). Screenshot to verify.")
    }

    private func executePressKey(input: [String: Any]) async throws -> ToolResult {
        guard let key = input["key"] as? String, !key.isEmpty else {
            return .error("press_key requires a key name (return, escape, delete, tab, arrows)")
        }
        let result = try await inputController.pressKey(key)
        return .text("\(result). Screenshot to verify.")
    }

    private func executeOpenApp(input: [String: Any]) async throws -> ToolResult {
        guard let name = input["name"] as? String else {
            return .error("open_app requires name parameter")
        }

        var args = [name]
        // open-app.sh expects the literal flag "--spotlight", not the raw method value
        if let method = input["method"] as? String, method == "spotlight" {
            args.append("--spotlight")
        }

        let result = try await scriptRunner.run(
            script: "open-app.sh", args: args, timeout: Constants.defaultScriptTimeout)
        let output = result.stdout.isEmpty ? "Opened \(name)" : result.stdout
        return .text("\(output). Screenshot needed to check for overlay prompts.")
    }

    private func executeHome() async throws -> ToolResult {
        _ = try await inputController.clickViewMenuItem("Home Screen")
        return .text("Went to Home Screen. Screenshot to verify.")
    }

    private func executeAppSwitcher() async throws -> ToolResult {
        _ = try await inputController.clickViewMenuItem("App Switcher")
        return .text("Opened App Switcher. Screenshot to verify.")
    }

    private func executeStatus() async throws -> ToolResult {
        let result = try await scriptRunner.run(script: "status.sh")
        return .text(result.stdout)
    }

    private func executeScanApps(input: [String: Any]) async throws -> ToolResult {
        var args = ["scan"]
        if let maxPages = numberValue(input["max_pages"]) {
            args.append(maxPages)
        }
        let result = try await scriptRunner.run(script: "registry.sh", args: args, timeout: Constants.scanTimeout)
        return .text(result.stdout)
    }

    private func executeListApps() async throws -> ToolResult {
        let result = try await scriptRunner.run(script: "registry.sh", args: ["list"])
        return .text(result.stdout)
    }

    // MARK: - Helpers

    private func intValue(_ value: Any?) -> Int? {
        if let intVal = value as? Int { return intVal }
        if let dblVal = value as? Double { return Int(dblVal) }
        if let strVal = value as? String { return Int(strVal) }
        return nil
    }

    private func numberValue(_ value: Any?) -> String? {
        if let intVal = value as? Int { return String(intVal) }
        if let dblVal = value as? Double { return String(Int(dblVal)) }
        if let strVal = value as? String { return strVal }
        return nil
    }
}
// swiftlint:enable type_body_length

/// Foreground or background the iPhone Mirroring app (backgrounding = activate
/// Finder, harmless and always running). Used by the black-frame retry ladder.
@MainActor
private func setMirroringActive(_ active: Bool) {
    let apps = NSWorkspace.shared.runningApplications
    if active {
        apps.first { $0.bundleIdentifier == Constants.iphoneMirroringBundleId }?
            .activate(options: .activateIgnoringOtherApps)
    } else if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        == Constants.iphoneMirroringBundleId {
        apps.first { $0.bundleIdentifier == "com.apple.finder" }?
            .activate(options: .activateIgnoringOtherApps)
    }
}

/// Cheap sampled-brightness check (~500 pixels) for an all-black frame.
private func isMostlyBlackFrame(_ data: Data) -> Bool {
    guard let rep = NSBitmapImageRep(data: data) else { return false }
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    guard width > 0, height > 0 else { return true }
    let step = max(1, min(width, height) / 22)
    var total = 0.0
    var count = 0
    var rowY = 0
    while rowY < height {
        var colX = 0
        while colX < width {
            if let color = rep.colorAt(x: colX, y: rowY)?.usingColorSpace(.deviceRGB) {
                total += Double(max(color.redComponent, color.greenComponent, color.blueComponent))
                count += 1
            }
            colX += step
        }
        rowY += step
    }
    guard count > 0 else { return true }
    return total / Double(count) < 0.04
}
