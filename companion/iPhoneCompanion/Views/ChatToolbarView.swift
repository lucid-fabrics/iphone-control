import SwiftUI

/// The header/toolbar bar for the chat view. Doubles as the window drag region
/// (the hidden titlebar's top strip stays draggable).
struct ChatToolbarView: View {
    let showSettings: Bool
    let onBack: () -> Void
    let onClear: () -> Void
    let onSettings: () -> Void
    let onDock: () -> Void

    // Clears the single close button at top-left (miniaturize/zoom are hidden).
    private let leadingInset: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            if showSettings {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(Theme.Font.title)

                Spacer()
                // Balance the back-button width so the title stays centered. Height
                // MUST be constrained: an unconstrained Color.clear is vertically
                // greedy and stretched the whole toolbar to half the panel, which
                // centered the title ~200px down in Settings.
                Color.clear.frame(width: 50, height: 0)
            } else {
                // No title chrome (Raycast-style): the top is a clean drag region
                // with only the essential controls, right-aligned.
                Spacer()

                HStack(spacing: 2) {
                    toolbarButton(icon: "rectangle.righthalf.inset.filled.arrow.right",
                                  help: "Dock (Cmd+D)", label: "Dock", action: onDock)
                        .keyboardShortcut("d", modifiers: .command)

                    toolbarButton(icon: "trash", help: "Clear chat", label: "Clear chat", action: onClear)

                    toolbarButton(icon: "gearshape.fill", help: "Settings", label: "Settings", action: onSettings)
                }
            }
        }
        .padding(.leading, showSettings ? 14 : leadingInset)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        // No fill: the top strip stays the SAME continuous material as the body
        // (a raised fill here read as two-tone banding against the panel).
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func toolbarButton(icon: String, help: String, label: String,
                               action: @escaping () -> Void) -> some View {
        ToolbarIconButton(icon: icon, help: help, label: label, action: action)
    }
}

/// Icon button with a proper hover state (macOS reads missing hover as broken)
/// and a VoiceOver label.
private struct ToolbarIconButton: View {
    let icon: String
    let help: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(hovering ? Theme.hairline : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}
