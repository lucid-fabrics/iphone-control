import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var appeared = false

    // Compiled once, not per render. These strip the model's internal tags before display.
    private static let cleanupPatterns: [NSRegularExpression] = {
        let sources = [
            #"<think>[\s\S]*?</think>"#,
            #"<minimax:tool_call>[\s\S]*?</minimax:tool_call>"#,
            #"<invoke[\s\S]*?</invoke>"#
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    private func cleanDisplayText(_ text: String) -> String {
        var cleaned = text
        for regex in Self.cleanupPatterns {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return cleaned
    }

    /// Inline markdown (bold, italic, code, links) with whitespace and newlines
    /// preserved, so AI replies stop showing raw ** and backticks. Falls back to
    /// plain text if the string is not valid markdown.
    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.content) { block in
                switch block {
                case .text(let text):
                    textBubble(text, isUser: message.role == .user)
                case .image(let data):
                    ScreenshotBubble(data: data)
                case .toolCall(_, let name, let status):
                    toolStatusView(name: name, status: status)
                }
            }
        }
        .padding(.horizontal, 14)
        .contextMenu {
            // The non-activating panel can't do native text selection, so offer an
            // explicit copy instead.
            if !message.plainText.isEmpty {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(message.plainText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: - Text Bubble

    @ViewBuilder
    private func textBubble(_ text: String, isUser: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 50) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 24, height: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                }
                .offset(y: -2)
                .accessibilityHidden(true)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                let displayText = isUser ? text : cleanDisplayText(text)

                if !displayText.isEmpty {
                    Text(attributed(displayText))
                        .textSelection(.enabled)
                        .font(Theme.Font.body)
                        .lineSpacing(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isUser
                                ? AnyShapeStyle(Theme.userBubbleGradient)
                                : AnyShapeStyle(Theme.aiBubble)
                        )
                        .foregroundStyle(isUser ? Theme.onAccent : Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isUser ? Color.clear : Theme.hairline, lineWidth: 0.5)
                        )

                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                }
            }

            if !isUser { Spacer(minLength: 50) }
        }
    }

    // MARK: - Tool Status

    @ViewBuilder
    private func toolStatusView(name: String, status: ToolStatus) -> some View {
        HStack(spacing: 8) {
            ZStack {
                switch status {
                case .running:
                    SpinnerRing(icon: toolIcon(name))
                case .completed:
                    Circle().fill(Theme.statusLive.opacity(0.15)).frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.statusLive)
                case .failed:
                    Circle().fill(Theme.statusError.opacity(0.15)).frame(width: 20, height: 20)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.statusError)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(toolDisplayName(name))
                    .font(Theme.Font.caption)
                    .foregroundStyle(status.themeColor)

                if case .failed(let error) = status {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.statusError.opacity(0.85))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(status.themeColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(status.themeColor.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    // Flat name->icon lookup; one case per tool.
    // swiftlint:disable:next cyclomatic_complexity
    private func toolIcon(_ name: String) -> String {
        switch name {
        case "screenshot": return "camera"
        case "tap": return "hand.tap"
        case "tap_text": return "text.viewfinder"
        case "tap_element": return "number.circle"
        case "run_steps": return "list.number"
        case "open_url": return "link"
        case "scroll", "scroll_to": return "arrow.up.arrow.down"
        case "read": return "doc.text.magnifyingglass"
        case "wait": return "hourglass"
        case "long_press": return "hand.tap.fill"
        case "back": return "chevron.backward"
        case "clear_text": return "xmark.circle"
        case "double_tap": return "hand.tap"
        case "press_key": return "keyboard"
        case "swipe": return "hand.draw"
        case "type_text": return "keyboard"
        case "open_app": return "app"
        case "home": return "house"
        case "app_switcher": return "square.stack.3d.up"
        case "find_window": return "macwindow"
        case "status": return "info.circle"
        case "scan_apps", "map_apps": return "magnifyingglass"
        case "list_apps": return "list.bullet"
        default: return "gearshape"
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case "screenshot": return "Capturing screen..."
        case "tap": return "Tapping..."
        case "tap_text": return "Tapping text..."
        case "tap_element": return "Tapping element..."
        case "run_steps": return "Running steps..."
        case "open_url": return "Opening link..."
        case "scroll": return "Scrolling..."
        case "scroll_to": return "Scrolling to find..."
        case "read": return "Reading screen..."
        case "wait": return "Waiting..."
        case "long_press": return "Long-pressing..."
        case "back": return "Going back..."
        case "clear_text": return "Clearing field..."
        case "double_tap": return "Double-tapping..."
        case "press_key": return "Pressing key..."
        case "swipe": return "Swiping..."
        case "type_text": return "Typing text..."
        case "open_app": return "Opening app..."
        case "home": return "Going home..."
        case "app_switcher": return "App switcher..."
        case "find_window": return "Finding window..."
        case "status": return "Checking status..."
        case "scan_apps", "map_apps": return "Scanning apps..."
        case "list_apps": return "Listing apps..."
        default: return "\(name)..."
        }
    }
}

/// Self-animating spinner for a running tool. Fixes the previously-frozen arc
/// (its rotation state was declared but never driven).
private struct SpinnerRing: View {
    let icon: String
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.2), lineWidth: 2)
                .frame(width: 20, height: 20)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .onAppear { spin = true }
    }
}

// MARK: - Tool Status color mapping

extension ToolStatus {
    var themeColor: Color {
        switch self {
        case .running: return Theme.accent
        case .completed: return Theme.statusLive
        case .failed: return Theme.statusError
        }
    }
}

/// Screenshots are collapsed to a small chip by default: the verification loop
/// takes one after every action, and rendering each full-size floods the chat.
/// The image is still sent to the model; this only changes what the UI draws.
/// Tap to expand any individual capture.
private struct ScreenshotBubble: View {
    let data: Data
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if expanded, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 8))
                    Text(expanded ? "Hide screenshot" : "Screenshot")
                        .font(Theme.Font.micro)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Theme.raised)
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .accessibilityLabel("iPhone screenshot, collapsed")
    }
}
