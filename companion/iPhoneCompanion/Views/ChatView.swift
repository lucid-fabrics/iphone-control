import SwiftUI

struct ChatView: View {
    @EnvironmentObject var conversation: Conversation
    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        // A plain top-to-bottom VStack as the root guarantees the header sits at
        // the top by construction. The glass is its .background so it fills behind.
        VStack(spacing: 0) {
            ChatToolbarView(
                showSettings: showSettings,
                onBack: { showSettings = false },
                onClear: {
                    withAnimation(.spring(response: 0.3)) {
                        conversation.clearHistory()
                    }
                },
                onSettings: { showSettings = true },
                onDock: { redock() },
                onCopy: { copyTranscript() }
            )
            .zIndex(1)

            if showSettings {
                SettingsView()
                    .transition(.opacity)
            } else {
                chatContent
                    .transition(.opacity)
            }
        }
        .background {
            // Real vibrancy blurs the desktop behind the non-opaque panel, with a
            // dense legibility tint over it.
            ZStack {
                VisualEffectBackground()
                Theme.surfaceTint
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
        .overlay(alignment: .top) {
            // Lit-glass top edge: a faint highlight fading down a few points.
            LinearGradient(colors: [Theme.topSheen, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .strokeBorder(Theme.bezel, lineWidth: 1)
        )
        .ignoresSafeArea()
        .tint(Theme.accent)
        .frame(minWidth: 320, minHeight: 400)
        .onAppear {
            isInputFocused = true
            conversation.loadAllAPIKeys()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSettings)
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if conversation.messages.isEmpty {
                            emptyStateView
                        }

                        ForEach(conversation.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if conversation.isProcessing {
                            thinkingIndicator
                                .id("loading")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: conversation.isProcessing) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            // Bottom area
            VStack(spacing: 0) {
                if !conversation.messages.isEmpty && !conversation.isProcessing {
                    SuggestionChipsView { suggestion in
                        sendMessage(suggestion)
                    }
                }

                ModelConfigView()

                ChatInputView(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    isProcessing: conversation.isProcessing,
                    onSend: sendCurrentMessage,
                    onCancel: { conversation.cancel() }
                )
            }
            .background(Theme.raised)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 64, height: 64)

                Image(systemName: "iphone.gen3")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.accentGradient)
            }

            VStack(spacing: 6) {
                Text("Control Your iPhone")
                    .font(.system(size: 16, weight: .semibold))
                Text("Type a command or tap a suggestion below")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            SuggestionChipsView { suggestion in
                sendMessage(suggestion)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                        .scaleEffect(conversation.isProcessing ? 1.3 : 0.8)
                        .opacity(conversation.isProcessing ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: conversation.isProcessing
                        )
                }
            }
            Text("Thinking")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.accentSoft))
        .padding(.horizontal, 14)
    }

    // MARK: - Actions

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sendMessage(text)
    }

    private func sendMessage(_ text: String) {
        inputText = ""
        conversation.send(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if conversation.isProcessing {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("loading", anchor: .bottom) }
        } else if let last = conversation.messages.last {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private func redock() {
        (NSApp.delegate as? AppDelegate)?.redock()
    }

    /// Copy the whole conversation to the clipboard. The non-activating panel can't
    /// do native select-all, so this is the way to grab everything at once.
    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(conversation.transcript, forType: .string)
    }
}
