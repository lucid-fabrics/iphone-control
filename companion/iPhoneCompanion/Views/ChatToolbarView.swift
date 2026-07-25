import SwiftUI

/// The header/toolbar bar for the chat view.
struct ChatToolbarView: View {
    let showSettings: Bool
    let onBack: () -> Void
    let onClear: () -> Void
    let onSettings: () -> Void
    let onDock: () -> Void

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
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
                // Balance the back button width
                Color.clear.frame(width: 50)
            } else {
                // App icon + title
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("iPhone Companion")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                HStack(spacing: 2) {
                    toolbarButton(icon: "rectangle.righthalf.inset.filled.arrow.right", help: "Dock (Cmd+D)", action: onDock)
                        .keyboardShortcut("d", modifiers: .command)

                    toolbarButton(icon: "trash", help: "Clear chat", action: onClear)

                    toolbarButton(icon: "gearshape.fill", help: "Settings", action: onSettings)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.8)
                    .background(.ultraThinMaterial)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
