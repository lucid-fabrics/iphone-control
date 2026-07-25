import SwiftUI

/// The input bar at the bottom of the chat view (text field + send/stop button).
struct ChatInputView: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let isProcessing: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    Text("Message...")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                        .padding(.leading, 12)
                }

                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(isInputFocused)
                    .onSubmit { onSend() }
                    .disabled(isProcessing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                isInputFocused.wrappedValue
                                    ? Color.accentColor.opacity(0.4)
                                    : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeOut(duration: 0.2), value: isInputFocused.wrappedValue)

            // Send / Stop button
            if isProcessing {
                Button(action: onCancel) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 30, height: 30)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(
                                canSend
                                    ? LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 30, height: 30)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(canSend ? .white : .gray.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
                .scaleEffect(canSend ? 1.0 : 0.92)
                .animation(.spring(response: 0.25), value: canSend)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
