import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var appeared = false

    /// Cleans AI response text by removing internal tags like <think>, tool calls, etc.
    private func cleanDisplayText(_ text: String) -> String {
        var cleaned = text
        
        // Remove <think>...</think> blocks (model's internal reasoning)
        let thinkPattern = #"<think>[\s\S]*?</think>"#
        if let regex = try? NSRegularExpression(pattern: thinkPattern, options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        
        // Remove <minimax:tool_call>...</minimax:tool_call> blocks
        let toolCallPattern = #"<minimax:tool_call>[\s\S]*?</minimax:tool_call>"#
        if let regex = try? NSRegularExpression(pattern: toolCallPattern, options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        
        // Remove any <invoke>...</invoke> blocks
        let invokePattern = #"<invoke[\s\S]*?</invoke>"#
        if let regex = try? NSRegularExpression(pattern: invokePattern, options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        
        // Trim excessive whitespace/newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Collapse multiple newlines into max 2
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.content) { block in
                switch block {
                case .text(let text):
                    textBubble(text, isUser: message.role == .user)

                case .image(let data):
                    imageBubble(data)

                case .toolCall(_, let name, let status):
                    toolStatusView(name: name, status: status)
                }
            }
        }
        .padding(.horizontal, 14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Text Bubble

    @ViewBuilder
    private func textBubble(_ text: String, isUser: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 50) }

            if !isUser {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .offset(y: -2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                let displayText = isUser ? text : cleanDisplayText(text)
                
                // Skip empty messages after cleaning
                if !displayText.isEmpty {
                    Text(displayText)
                        .textSelection(.enabled)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isUser
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                        )
                        .foregroundStyle(isUser ? .white : .primary)
                        .clipShape(BubbleShape(isUser: isUser))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)

                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 4)
                }
            }

            if !isUser { Spacer(minLength: 50) }
        }
    }

    // MARK: - Image Bubble

    @ViewBuilder
    private func imageBubble(_ data: Data) -> some View {
        if let nsImage = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 8))
                    Text("Screenshot")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Tool Status

    @ViewBuilder
    private func toolStatusView(name: String, status: ToolStatus) -> some View {
        HStack(spacing: 8) {
            // Icon with animated ring for running state
            ZStack {
                switch status {
                case .running:
                    Circle()
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(spinnerRotation))
                    Image(systemName: toolIcon(name))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                case .completed:
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                case .failed:
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(toolDisplayName(name))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(status.color)

                if case .failed(let error) = status {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(status.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(status.borderColor, lineWidth: 0.5)
                )
        )
    }

    @State private var spinnerRotation: Double = 0

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "screenshot": return "camera"
        case "tap": return "hand.tap"
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

    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case "screenshot": return "Capturing screen..."
        case "tap": return "Tapping..."
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

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let tail: CGFloat = 4

        var path = Path()

        if isUser {
            // Rounded rect with tail on bottom-right
            path.addRoundedRect(in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width - tail,
                height: rect.height
            ), cornerSize: CGSize(width: r, height: r))
            // Small tail
            path.move(to: CGPoint(x: rect.maxX - tail, y: rect.maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tail, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tail - 6, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tail - 2, y: rect.maxY)
            )
        } else {
            // Rounded rect with tail on bottom-left
            path.addRoundedRect(in: CGRect(
                x: rect.minX + tail,
                y: rect.minY,
                width: rect.width - tail,
                height: rect.height
            ), cornerSize: CGSize(width: r, height: r))
            // Small tail
            path.move(to: CGPoint(x: rect.minX + tail, y: rect.maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.minX + tail, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + tail + 6, y: rect.maxY),
                control: CGPoint(x: rect.minX + tail + 2, y: rect.maxY)
            )
        }

        return path
    }
}

// MARK: - Tool Status Extensions

extension ToolStatus {
    var color: Color {
        switch self {
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }

    var backgroundColor: Color {
        switch self {
        case .running: return Color.accentColor.opacity(0.05)
        case .completed: return Color.green.opacity(0.05)
        case .failed: return Color.red.opacity(0.05)
        }
    }

    var borderColor: Color {
        switch self {
        case .running: return Color.accentColor.opacity(0.15)
        case .completed: return Color.green.opacity(0.15)
        case .failed: return Color.red.opacity(0.15)
        }
    }
}
