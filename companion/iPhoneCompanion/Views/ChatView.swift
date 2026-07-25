import SwiftUI

struct ChatView: View {
    @EnvironmentObject var conversation: Conversation
    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
                    onDock: { redock() }
                )
                .zIndex(1)

                if showSettings {
                    SettingsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    chatContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
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
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        .background(.ultraThinMaterial)
                }
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
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
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.15), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "iphone.gen3")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("Control Your iPhone")
                    .font(.system(size: 16, weight: .semibold))
                Text("Type a command or tap a suggestion below")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .scaleEffect(conversation.isProcessing ? 1.3 : 0.8)
                        .opacity(conversation.isProcessing ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                            value: conversation.isProcessing
                        )
                }
            }
            Text("Thinking")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.06))
        )
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
}
