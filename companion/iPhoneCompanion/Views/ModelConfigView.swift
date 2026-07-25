import SwiftUI

struct ModelConfigView: View {
    @EnvironmentObject var conversation: Conversation

    @State private var showModelConfig = false

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed bar — tap to expand
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showModelConfig.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(currentModelDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.aiBackend.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )

                    Image(systemName: showModelConfig ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded config panel
            if showModelConfig {
                modelConfigPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var currentModelDisplay: String {
        switch conversation.aiBackend {
        case .claudeCode: return conversation.claudeModel
        case .claude: return conversation.claudeModel
        case .openRouter: return conversation.openRouterModel
        case .minimax: return conversation.minimaxModel
        case .ollama: return conversation.ollamaModel
        }
    }

    private var modelConfigPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Provider picker
            HStack(spacing: 6) {
                ForEach(AIBackend.allCases, id: \.self) { backend in
                    Button {
                        conversation.aiBackend = backend
                    } label: {
                        Text(backend.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(conversation.aiBackend == backend
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.primary.opacity(0.04))
                            )
                            .foregroundStyle(conversation.aiBackend == backend
                                ? Color.accentColor
                                : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Model field
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                switch conversation.aiBackend {
                case .claudeCode:
                    TextField("e.g. claude-sonnet-4-6", text: $conversation.claudeModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                case .openRouter:
                    TextField("e.g. anthropic/claude-sonnet-4.6", text: $conversation.openRouterModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .onChange(of: conversation.openRouterModel) { _, _ in
                            conversation.modelSupportsVision = nil
                        }
                case .claude:
                    TextField("e.g. claude-sonnet-4-6-20250514", text: $conversation.claudeModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                case .ollama:
                    TextField("e.g. llama3.1", text: $conversation.ollamaModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                case .minimax:
                    TextField("e.g. MiniMax-M2.5", text: $conversation.minimaxModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )

            // Claude Code auth status
            if conversation.aiBackend == .claudeCode {
                claudeCodeAuthStatus
            }

            // API key field (for Claude / OpenRouter / MiniMax)
            if conversation.aiBackend == .claude || conversation.aiBackend == .openRouter || conversation.aiBackend == .minimax {
                apiKeyRow
            }

            // Ollama URL
            if conversation.aiBackend == .ollama {
                ollamaURLRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Subviews

    private var claudeCodeAuthStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let creds = ClaudeCodeAuthHelper.loadCredentials() {
                let isValid = creds.expiresAt.timeIntervalSinceNow > 0
                HStack(spacing: 4) {
                    Text(creds.subscriptionType)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isValid ? .green : .orange)
                    Text(isValid ? "Connected" : "Expired")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isValid ? .green : .orange)
                }
            } else {
                Text("Not found — run `claude` in terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var apiKeyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if conversation.aiBackend == .claude {
                SecureField("sk-ant-api03-...", text: Binding(
                    get: { conversation.loadAPIKey(for: .claude) },
                    set: { conversation.saveAPIKey($0, for: .claude) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
            } else if conversation.aiBackend == .openRouter {
                SecureField("sk-or-...", text: Binding(
                    get: { conversation.loadAPIKey(for: .openRouter) },
                    set: { conversation.saveAPIKey($0, for: .openRouter) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
            } else if conversation.aiBackend == .minimax {
                SecureField("sk-cp-...", text: Binding(
                    get: { conversation.loadAPIKey(for: .minimax) },
                    set: { conversation.saveAPIKey($0, for: .minimax) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
            }

            if conversation.hasAPIKey {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var ollamaURLRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("http://localhost:11434", text: $conversation.ollamaURL)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
