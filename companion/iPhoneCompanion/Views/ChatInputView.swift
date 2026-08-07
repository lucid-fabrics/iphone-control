import SwiftUI

/// The input bar at the bottom of the chat view (text field + send/stop button).
struct ChatInputView: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let isProcessing: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @State private var sendHovering = false

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    Text("Message...")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 12)
                }

                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .focused(isInputFocused)
                    .onSubmit { onSend() }
                    .disabled(isProcessing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isInputFocused.wrappedValue ? Theme.accent.opacity(0.55) : Theme.hairline,
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeOut(duration: 0.2), value: isInputFocused.wrappedValue)

            if isProcessing {
                Button(action: onCancel) {
                    circleButton(fill: AnyShapeStyle(Theme.statusError), symbol: "stop.fill", size: 11)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Stop")
            } else {
                Button(action: onSend) {
                    circleButton(
                        fill: canSend ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.raised),
                        symbol: "arrow.up",
                        size: 13,
                        tint: canSend ? Theme.onAccent : Theme.textTertiary
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
                .scaleEffect(canSend ? (sendHovering ? 1.08 : 1.0) : 0.92)
                .animation(.spring(response: 0.25), value: canSend)
                .animation(.spring(response: 0.25), value: sendHovering)
                .onHover { sendHovering = $0 && canSend }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func circleButton(fill: AnyShapeStyle, symbol: String, size: CGFloat,
                              tint: Color = .white) -> some View {
        ZStack {
            Circle().fill(fill).frame(width: 30, height: 30)
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}
