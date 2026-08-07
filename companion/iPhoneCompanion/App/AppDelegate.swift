import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let conversation = Conversation()
    private let windowManager = WindowManager()
    private lazy var follower = WindowFollower(windowManager: windowManager)

    // Flush against the mirror edge so the two windows read as one object. Kept a
    // named constant: nudge negative if the mirror's shadow ever reads as a seam.
    // ponytail: flush dock, tune dockGutter if the shadow shows.
    private let dockGutter: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let chatView = ChatView()
            .environmentObject(conversation)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel,
                        .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        // Glass: the panel itself is transparent so the SwiftUI content's own
        // vibrant material and rounded clip define the whole surface, reading as
        // one continuous glass object with the phone. The titlebar is hidden but
        // its top strip stays a drag handle (standard hidden-titlebar pattern);
        // .nonactivatingPanel is preserved so clicks never steal focus from Mirroring.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // A floating console does not minimize or zoom; keep only close so the top
        // strip stays clean. Header content is inset to clear the close button.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: chatView)
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.contentMinSize = NSSize(width: 320, height: 400)
        panel.isReleasedWhenClosed = false

        self.panel = panel

        dockToiPhoneMirroring()
        panel.orderFrontRegardless()

        // Always follow the mirror. (Detach-on-user-drag was removed: its didMove
        // detection false-triggered and left the follower stuck, which broke
        // following entirely. Re-dock via Cmd+D is unaffected.)
        follower.start { [weak self] in self?.dockToiPhoneMirroring() }

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
            // Closed / minimized / shrunk below the guard: hide rather than jump.
            panel.orderOut(nil)
            return
        }

        // CGWindow frames are global top-left coords; the AppKit flip must use the
        // PRIMARY screen height (screens.first), not NSScreen.main (the focused screen),
        // or the panel lands wrong whenever iPhone Mirroring sits on another display.
        guard let primary = NSScreen.screens.first else { return }
        let screenHeight = primary.frame.height

        let panelWidth = panel.frame.width
        // Top-align the panel with the mirror. When the mirror is shorter than our
        // min height, the panel spills BELOW rather than shoving its top above the
        // mirror's top: the shared top edge is what sells "one continuous object".
        let usedHeight = max(frame.size.height, panel.contentMinSize.height)

        // Default to the right of the mirror; flip left if that would run off the
        // screen the mirror sits on.
        var panelX = frame.origin.x + frame.size.width + dockGutter
        let mirrorScreen = NSScreen.screens.first { $0.frame.intersects(
            NSRect(x: frame.origin.x, y: screenHeight - frame.origin.y - frame.size.height,
                   width: frame.size.width, height: frame.size.height)
        )} ?? primary
        if panelX + panelWidth > mirrorScreen.visibleFrame.maxX {
            panelX = frame.origin.x - dockGutter - panelWidth
        }

        let panelY = screenHeight - frame.origin.y - usedHeight

        let target = NSRect(x: panelX, y: panelY, width: panelWidth, height: usedHeight)
        panel.setFrame(target, display: true, animate: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    @objc func redock() {
        dockToiPhoneMirroring()
    }
}
