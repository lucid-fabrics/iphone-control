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
        if let result = nativeFindWindow() { return result }
        let result = try await scriptRunner.run(script: "find-window.sh")
        return .text(result.stdout)
    }

    private func executeScreenshot() async throws -> ToolResult {
        if let result = nativeScreenshot() { return result }
        // Fallback: shell script
        let tmpPath = "/tmp/iphone-companion-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let result = try await scriptRunner.run(script: "screenshot.sh", args: [tmpPath])
        let outputPath = result.stdout.isEmpty ? tmpPath : result.stdout
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)) else {
            return .error("Screenshot captured but file not readable")
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

        let mx = Int(rect.width * 0.06)
        let mt = Int(rect.height * 0.09)
        let mb = Int(rect.height * 0.04)

        let json = """
        {"window_x":\(Int(rect.minX)),"window_y":\(Int(rect.minY)),"window_width":\(Int(rect.width)),"window_height":\(Int(rect.height)),"content_x":\(Int(rect.minX) + mx),"content_y":\(Int(rect.minY) + mt),"content_width":\(Int(rect.width) - mx * 2),"content_height":\(Int(rect.height) - mt - mb)}
        """
        return .text(json)
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
        let mx = Int(rect.width * 0.06 * pixelScale)
        let mt = Int(rect.height * 0.09 * pixelScale)
        let mb = Int(rect.height * 0.04 * pixelScale)
        let cropRect = CGRect(
            x: mx, y: mt,
            width: cgImage.width - mx * 2,
            height: cgImage.height - mt - mb
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
        guard let x = intValue(input["x"]),
              let y = intValue(input["y"]) else {
            return .error("tap requires x and y coordinates")
        }
        _ = try await inputController.tap(x: x, y: y)
        return .text("Tapped at (\(x), \(y)). Screenshot to verify.")
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
        guard let x1 = intValue(input["x1"]),
              let y1 = intValue(input["y1"]),
              let x2 = intValue(input["x2"]),
              let y2 = intValue(input["y2"]) else {
            return .error("swipe requires x1, y1, x2, y2 coordinates")
        }
        let duration = intValue(input["duration_ms"]) ?? Constants.defaultSwipeDuration
        _ = try await inputController.swipe(x1: x1, y1: y1, x2: x2, y2: y2, durationMs: duration)
        return .text("Swiped from (\(x1),\(y1)) to (\(x2),\(y2)). Screenshot to verify.")
    }

    private func executeTypeText(input: [String: Any]) async throws -> ToolResult {
        guard let text = input["text"] as? String else {
            return .error("type_text requires text parameter")
        }
        let tapX = intValue(input["x"])
        let tapY = intValue(input["y"])
        _ = try await inputController.typeText(text, tapX: tapX, tapY: tapY)
        return .text("Typed: \"\(text)\". Screenshot to verify.")
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

        let result = try await scriptRunner.run(script: "open-app.sh", args: args, timeout: Constants.defaultScriptTimeout)
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
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func numberValue(_ value: Any?) -> String? {
        if let n = value as? Int { return String(n) }
        if let n = value as? Double { return String(Int(n)) }
        if let s = value as? String { return s }
        return nil
    }
}
