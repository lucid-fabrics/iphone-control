import SwiftUI

struct SuggestionChipsView: View {
    let onSelect: (String) -> Void

    private let suggestions: [(icon: String, text: String)] = [
        ("camera.fill", "Take a screenshot"),
        ("app.badge", "Open Settings"),
        ("house.fill", "Go home"),
        ("magnifyingglass", "Scan my apps"),
        ("info.circle", "Check status"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.text) { suggestion in
                    Button {
                        onSelect(suggestion.text)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(suggestion.text)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.08))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}
