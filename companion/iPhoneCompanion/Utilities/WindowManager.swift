import CoreGraphics
import AppKit

/// PIDs of the running iPhone Mirroring process(es), looked up once per window scan.
/// Matches the bundle ID, never kCGWindowOwnerName, which is localized (e.g. Japanese macOS).
func mirroringPIDs() -> Set<Int> {
    Set(NSRunningApplication.runningApplications(withBundleIdentifier: Constants.iphoneMirroringBundleId)
        .map { Int($0.processIdentifier) })
}

class WindowManager {
    struct WindowFrame {
        let origin: CGPoint
        let size: CGSize
    }

    func findIPhoneMirroringFrame() -> WindowFrame? {
        if let frame = findViaCGWindowList() { return frame }
        if let frame = findViaHelper() { return frame }
        if let frame = findViaAccessibility() { return frame }
        return nil
    }

    private func findViaCGWindowList() -> WindowFrame? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let pids = mirroringPIDs()
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int, pids.contains(pid),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = numericValue(bounds["X"]),
                  let y = numericValue(bounds["Y"]),
                  let width = numericValue(bounds["Width"]),
                  let height = numericValue(bounds["Height"])
            else { continue }

            return WindowFrame(
                origin: CGPoint(x: x, y: y),
                size: CGSize(width: width, height: height)
            )
        }
        return nil
    }

    private func findViaHelper() -> WindowFrame? {
        let scriptsPath = UserDefaults.standard.string(forKey: "scriptsPath") ?? Constants.defaultScriptsPath
        let helperPath = (scriptsPath as NSString).appendingPathComponent("helpers/get-window-id")
        let helperSrc = helperPath + ".swift"

        if !FileManager.default.fileExists(atPath: helperPath),
           FileManager.default.fileExists(atPath: helperSrc) {
            let compile = Process()
            compile.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
            compile.arguments = ["-O", helperSrc, "-o", helperPath]
            do {
                try compile.run()
                compile.waitUntilExit()
            } catch {
                NSLog("[Companion] Failed to compile get-window-id helper: %@", error.localizedDescription)
            }
        }

        guard FileManager.default.fileExists(atPath: helperPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

        let parts = output.split(separator: "|")
        guard parts.count >= 5,
              let x = Double(parts[1]),
              let y = Double(parts[2]),
              let width = Double(parts[3]),
              let height = Double(parts[4])
        else { return nil }

        return WindowFrame(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height)
        )
    }

    private func findViaAccessibility() -> WindowFrame? {
        guard let mirroringApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: Constants.iphoneMirroringBundleId
        ).first else { return nil }

        let appElement = AXUIElementCreateApplication(mirroringApp.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else { return nil }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        let positionValue = unsafeBitCast(positionRef, to: AXValue.self)
        let sizeValue = unsafeBitCast(sizeRef, to: AXValue.self)
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

        guard size.width > 0, size.height > 0 else { return nil }
        return WindowFrame(origin: position, size: size)
    }

    private func numericValue(_ value: Any?) -> CGFloat? {
        if let n = value as? CGFloat { return n }
        if let n = value as? Double { return CGFloat(n) }
        if let n = value as? Int { return CGFloat(n) }
        if let n = value as? NSNumber { return CGFloat(n.doubleValue) }
        return nil
    }
}
