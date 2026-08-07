import CoreGraphics
import AppKit
import ApplicationServices

class WindowManager {
    struct WindowFrame: Equatable {
        let origin: CGPoint
        let size: CGSize
    }

    // Windows below this in either dimension are the app's own phantom helper
    // windows, never the real mirror. Matches the guard in InputController and
    // helpers/input-src/window.swift.
    static let minWindowSide: CGFloat = 100

    func findIPhoneMirroringFrame() -> WindowFrame? {
        if let frame = findViaCGWindowList() { return frame }
        if let frame = findViaHelper() { return frame }
        if let frame = findViaAccessibility() { return frame }
        return nil
    }

    private func findViaCGWindowList() -> WindowFrame? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        guard let windowList = info as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "iPhone Mirroring",
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let winX = numericValue(bounds["X"]),
                  let winY = numericValue(bounds["Y"]),
                  let width = numericValue(bounds["Width"]),
                  let height = numericValue(bounds["Height"]),
                  width > Self.minWindowSide, height > Self.minWindowSide
            else { continue }

            return WindowFrame(
                origin: CGPoint(x: winX, y: winY),
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
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output = raw else { return nil }

        let parts = output.split(separator: "|")
        guard parts.count >= 5,
              let winX = Double(parts[1]),
              let winY = Double(parts[2]),
              let width = Double(parts[3]),
              let height = Double(parts[4]),
              width > Double(Self.minWindowSide), height > Double(Self.minWindowSide)
        else { return nil }

        return WindowFrame(
            origin: CGPoint(x: winX, y: winY),
            size: CGSize(width: width, height: height)
        )
    }

    /// The live AXUIElement for the mirroring window plus its owning pid. Used by
    /// WindowFollower to attach an observer and to re-read the frame cheaply.
    func mirroringWindowElement() -> (element: AXUIElement, pid: pid_t)? {
        let apps = NSWorkspace.shared.runningApplications
        guard let mirroringApp = apps.first(where: { $0.localizedName == "iPhone Mirroring" }) else { return nil }

        let appElement = AXUIElementCreateApplication(mirroringApp.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        // Skip phantom helper windows; the real mirror is the one bigger than the guard.
        for window in windows {
            if let frame = frame(of: window),
               frame.size.width > Self.minWindowSide, frame.size.height > Self.minWindowSide {
                return (window, mirroringApp.processIdentifier)
            }
        }
        return nil
    }

    /// Read position + size of a specific window element.
    func frame(of window: AXUIElement) -> WindowFrame? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        guard size.width > 0, size.height > 0 else { return nil }
        return WindowFrame(origin: position, size: size)
    }

    private func findViaAccessibility() -> WindowFrame? {
        guard let (element, _) = mirroringWindowElement() else { return nil }
        return frame(of: element)
    }

    private func numericValue(_ value: Any?) -> CGFloat? {
        if let num = value as? CGFloat { return num }
        if let num = value as? Double { return CGFloat(num) }
        if let num = value as? Int { return CGFloat(num) }
        if let num = value as? NSNumber { return CGFloat(num.doubleValue) }
        return nil
    }
}

/// Keeps a callback firing whenever the iPhone Mirroring window moves, resizes,
/// closes, or (re)launches, so a docked panel can stay glued to it.
///
/// Primary signal is an AXObserver on the mirroring window (event-driven, ~0 CPU
/// idle, continuous during a drag). A 1 Hz safety timer using a frame diff covers
/// the launch race (process up but window not yet), a silently-failed observer
/// registration, and any missed settle. NSWorkspace launch/terminate notifications
/// re-attach across a Mirroring quit and relaunch (the element is different each time).
@MainActor
final class WindowFollower {
    private let windowManager: WindowManager
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var lastFrame: WindowManager.WindowFrame?
    private var safetyTimer: Timer?
    private var onChange: (() -> Void)?

    /// When the user drags the panel away, following pauses until an explicit re-dock.
    var paused = false

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunchedOrTerminated(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appLaunchedOrTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        attach()

        // Uses the same frame-diff idea as find-window.sh's cache key.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
        onChange = nil
    }

    // MARK: - Observer lifecycle

    private func attach() {
        guard observer == nil, let (element, pid) = windowManager.mirroringWindowElement() else { return }

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let follower = Unmanaged<WindowFollower>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { follower.frameChanged() }
        }
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let axObserver = newObserver else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXMovedNotification, kAXResizedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(axObserver, element, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)

        observer = axObserver
        observedElement = element
        observedPID = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedElement = nil
        observedPID = nil
    }

    // MARK: - Change handling

    private func frameChanged() {
        // The destroyed notification arrives on the same element; re-resolve next tick.
        if observedElement == nil || windowManager.findIPhoneMirroringFrame() == nil {
            detach()
        }
        fire()
    }

    private func tick() {
        if observer == nil { attach() }               // launch-race / relaunch re-attach
        let frame = windowManager.findIPhoneMirroringFrame()
        if frame != lastFrame { fire() }
    }

    private func fire() {
        lastFrame = windowManager.findIPhoneMirroringFrame()
        guard !paused else { return }
        onChange?()
    }

    @objc private func appLaunchedOrTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Constants.iphoneMirroringBundleId
        else { return }
        detach()
        // Give SpringBoard a beat to create/destroy the window, then let tick() re-resolve.
        fire()
    }
}
