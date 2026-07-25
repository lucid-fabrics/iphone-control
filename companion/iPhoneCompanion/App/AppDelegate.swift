import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let conversation = Conversation()
    private let windowManager = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let chatView = ChatView()
            .environmentObject(conversation)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.title = "iPhone Companion"
        panel.contentView = NSHostingView(rootView: chatView)
        panel.contentMinSize = NSSize(width: 320, height: 400)
        panel.isReleasedWhenClosed = false

        self.panel = panel

        dockToiPhoneMirroring()
        panel.orderFrontRegardless()

        requestPermissions()
    }

    private func requestPermissions() {
        // Accessibility - prompts if not granted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        NSLog("[Companion] Accessibility granted: %d", accessibilityGranted)

        // Screen Recording - prompts if not granted
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted {
            CGRequestScreenCaptureAccess()
        }
        NSLog("[Companion] Screen Recording granted: %d", screenRecordingGranted)
    }

    func dockToiPhoneMirroring() {
        guard let frame = windowManager.findIPhoneMirroringFrame() else {
            panel.center()
            return
        }

        // CGWindow frames are global top-left coords; the AppKit flip must use the
        // PRIMARY screen height (screens.first), not NSScreen.main (the focused screen),
        // or the panel lands wrong whenever iPhone Mirroring sits on another display.
        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height

        let panelX = frame.origin.x + frame.size.width + 4
        let panelY = screenHeight - frame.origin.y - frame.size.height
        let panelHeight = frame.size.height

        panel.setFrame(
            NSRect(x: panelX, y: panelY, width: 380, height: panelHeight),
            display: true,
            animate: false
        )
    }

    @objc func redock() {
        dockToiPhoneMirroring()
    }
}
