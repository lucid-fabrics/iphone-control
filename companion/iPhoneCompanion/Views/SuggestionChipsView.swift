import SwiftUI

struct SuggestionChipsView: View {
    let onSelect: (String) -> Void

    private let suggestions: [(icon: String, text: String)] = [
        ("camera.fill", "Take a screenshot"),
        ("app.badge", "Open Settings"),
        ("house.fill", "Go home"),
        ("magnifyingglass", "Scan my apps"),
        ("info.circle", "Check status")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.text) { suggestion in
                    SuggestionChip(icon: suggestion.icon, text: suggestion.text) {
                        onSelect(suggestion.text)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

private struct SuggestionChip: View {
    let icon: String
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)   // one small accent cue, neutral otherwise
                Text(text)
                    .font(Theme.Font.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hovering ? Theme.accent.opacity(0.16) : Theme.raised)
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
            )
            .foregroundStyle(hovering ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
