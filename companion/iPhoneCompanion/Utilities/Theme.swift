import SwiftUI
import AppKit

/// Single source of truth for the companion's visual language: an "iOS glass"
/// identity that reads as an extension of the mirrored device. All colors adapt
/// to light and dark; nothing here is a raw inline literal at a call site.
enum Theme {

    // MARK: - Signature accent (the app's own identity, not the system accent)

    static let accent = dynamicColor(light: 0x5856D6, dark: 0x6E6CE8)      // indigo
    static let accentSoft = dynamicColor(light: 0x5856D6, dark: 0x6E6CE8, alpha: 0.14)
    static let accentGradient = LinearGradient(
        colors: [dynamicColor(light: 0x7A5AF8, dark: 0x8E7BFF),
                 dynamicColor(light: 0x5856D6, dark: 0x6E6CE8)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Surfaces and lines

    /// Dense tint over the window vibrancy: legible on ANY wallpaper. A thin tint
    /// let the desktop bleed through and killed contrast, which read as "window
    /// alpha set to 0.6" rather than designed glass. This is the biggest single
    /// lever on looking finished.
    static let surfaceTint = dynamicColor(light: 0xF4F4F6, dark: 0x1C1C20, alpha: 0.82)
    static let raised = dynamicColor(light: 0xFFFFFF, dark: 0x2C2C34, alpha: 0.6)
    static let hairline = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.10)
    static let bezel = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.16)
    /// Bright top-edge rim-light: the cue that says "glass" rather than matte panel.
    static let topSheen = dynamicColor(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.12)

    // MARK: - Text

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.4)
    static let onAccent = Color.white

    // MARK: - Bubbles

    static let aiBubble = dynamicColor(light: 0xFFFFFF, dark: 0x2E2E38, alpha: 0.7)
    static let userBubbleGradient = LinearGradient(
        colors: [dynamicColor(light: 0x5E8BFF, dark: 0x5E8BFF),
                 dynamicColor(light: 0x5856D6, dark: 0x6E6CE8)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Status

    static let statusLive = dynamicColor(light: 0x30B84A, dark: 0x32D74B)
    static let statusBusy = dynamicColor(light: 0xE68A00, dark: 0xFF9F0A)
    static let statusError = dynamicColor(light: 0xE0352B, dark: 0xFF453A)

    // MARK: - Radii

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let window: CGFloat = 18     // echoes the phone's rounded corners
    }

    // MARK: - Spacing

    enum Space {
        static let gutter: CGFloat = 14
        static let row: CGFloat = 10
        static let tight: CGFloat = 6
    }

    // MARK: - Type ramp

    enum Font {
        static let title = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium)
        static let micro = SwiftUI.Font.system(size: 9)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }

    // MARK: - Helpers

    static func dynamicColor(light: Int, dark: Int, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(hex: isDark ? dark : light, alpha: alpha)
        })
    }

    private static func nsColor(hex: Int, alpha: CGFloat) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A real vibrant material backing (NSVisualEffectView) so the panel genuinely
/// blurs the desktop behind it. Requires the host window to be non-opaque with a
/// clear background (set in AppDelegate).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

extension View {
    /// Standard hover-press affordance for controls (macOS reads missing hover as broken).
    func hoverLift(_ hovering: Bool) -> some View {
        self.scaleEffect(hovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}
