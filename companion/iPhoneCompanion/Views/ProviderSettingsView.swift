import SwiftUI

/// Individual provider configuration sections — legacy view kept for compatibility.
/// The main settings flow now uses SettingsView directly.
struct ProviderSettingsView: View {
    @EnvironmentObject var conversation: Conversation
    @Binding var showingClaudeKey: Bool
    @Binding var showingORKey: Bool
    @Binding var showingMinimaxKey: Bool
    @Binding var claudeModels: [ClaudeModel]
    @Binding var orModels: [ClaudeModel]
    @Binding var minimaxModels: [ClaudeModel]
    @Binding var claudeStatus: SettingsStatus
    @Binding var orStatus: SettingsStatus
    @Binding var minimaxStatus: SettingsStatus

    var body: some View {
        Group {
            if conversation.aiBackend == .claude {
                claudeSection
            }

            if conversation.aiBackend == .openRouter {
                openRouterSection
            }

            if conversation.aiBackend == .minimax {
                minimaxSection
            }

            if conversation.aiBackend == .ollama {
                ollamaSection
            }
        }
    }

    // MARK: - Claude Section

    private var claudeSection: some View {
        GroupBox("Claude API") {
            VStack(alignment: .leading, spacing: 8) {
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .claude) },
                        set: { conversation.saveAPIKey($0, for: .claude) }
                    ),
                    showing: $showingClaudeKey,
                    placeholder: "sk-ant-api03-..."
                )

                HStack {
                    Button("Save & Detect Models") {
                        claudeStatus = .validating
                        fetchClaudeModels()
                    }
                    .disabled(conversation.loadAPIKey(for: .claude).isEmpty)
                    statusIndicator(claudeStatus)
                }

                LabeledContent("Model") {
                    Picker("", selection: $conversation.claudeModel) {
                        if claudeModels.isEmpty {
                            ForEach(Constants.fallbackClaudeModels, id: \.id) { m in
                                Text(m.name).tag(m.id)
                            }
                        } else {
                            ForEach(claudeModels) { m in
                                Text(m.name).tag(m.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - OpenRouter Section

    private var openRouterSection: some View {
        GroupBox("OpenRouter") {
            VStack(alignment: .leading, spacing: 8) {
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .openRouter) },
                        set: { conversation.saveAPIKey($0, for: .openRouter) }
                    ),
                    showing: $showingORKey,
                    placeholder: "sk-or-..."
                )

                HStack {
                    Button("Save & Detect Models") {
                        orStatus = .validating
                        fetchORModels()
                    }
                    .disabled(conversation.loadAPIKey(for: .openRouter).isEmpty)
                    statusIndicator(orStatus)
                }

                LabeledContent("Model") {
                    Picker("", selection: $conversation.openRouterModel) {
                        if orModels.isEmpty {
                            ForEach(Constants.fallbackOpenRouterModels, id: \.id) { m in
                                Text(m.name).tag(m.id)
                            }
                        } else {
                            ForEach(orModels) { m in
                                Text(m.name).tag(m.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }

                Text("Get a key at openrouter.ai/keys — supports Claude, GPT, Gemini, and more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - MiniMax Section

    private var minimaxSection: some View {
        GroupBox("MiniMax") {
            VStack(alignment: .leading, spacing: 8) {
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .minimax) },
                        set: { conversation.saveAPIKey($0, for: .minimax) }
                    ),
                    showing: $showingMinimaxKey,
                    placeholder: "sk-cp-..."
                )

                HStack {
                    Button("Save & Detect Models") {
                        minimaxStatus = .validating
                        fetchMinimaxModels()
                    }
                    .disabled(conversation.loadAPIKey(for: .minimax).isEmpty)
                    statusIndicator(minimaxStatus)
                }

                LabeledContent("Model") {
                    Picker("", selection: $conversation.minimaxModel) {
                        if minimaxModels.isEmpty {
                            ForEach(Constants.fallbackMiniMaxModels, id: \.id) { m in
                                Text(m.name).tag(m.id)
                            }
                        } else {
                            ForEach(minimaxModels) { m in
                                Text(m.name).tag(m.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }

                Text("Get an API key from minimax.io")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Ollama Section

    private var ollamaSection: some View {
        GroupBox("Ollama") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Model") {
                    TextField("llama3.1", text: $conversation.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                }
                LabeledContent("URL") {
                    TextField("http://localhost:11434", text: $conversation.ollamaURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func apiKeyField(key: Binding<String>, showing: Binding<Bool>, placeholder: String) -> some View {
        HStack {
            if showing.wrappedValue {
                TextField(placeholder, text: key)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField(placeholder, text: key)
                    .textFieldStyle(.roundedBorder)
            }
            Button(showing.wrappedValue ? "Hide" : "Show") {
                showing.wrappedValue.toggle()
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func statusIndicator(_ status: SettingsStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .validating:
            ProgressView().scaleEffect(0.7)
            Text("Validating...").font(.caption).foregroundStyle(.secondary)
        case .valid:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Key saved").font(.caption).foregroundStyle(.green)
        case .invalid(let msg):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: - Model Fetching

    private func fetchClaudeModels() {
        Task {
            let apiKey = conversation.loadAPIKey(for: .claude)
            let result = await ModelFetcher.fetchModels(apiKey: apiKey)
            await MainActor.run {
                if !result.models.isEmpty {
                    claudeModels = result.models
                    claudeStatus = .valid
                    if !result.models.contains(where: { $0.id == conversation.claudeModel }) {
                        conversation.claudeModel = result.models.first(where: { $0.id.contains("sonnet") })?.id ?? result.models[0].id
                    }
                } else if let error = result.error {
                    claudeStatus = .invalid("\(error) — using defaults")
                } else {
                    claudeStatus = .valid
                }
            }
        }
    }

    private func fetchMinimaxModels() {
        Task {
            let apiKey = conversation.loadAPIKey(for: .minimax)
            let result = await ModelFetcher.fetchMinimaxModels(apiKey: apiKey)
            await MainActor.run {
                if !result.models.isEmpty {
                    minimaxModels = result.models
                    minimaxStatus = .valid
                    if !result.models.contains(where: { $0.id == conversation.minimaxModel }) {
                        conversation.minimaxModel = result.models[0].id
                    }
                } else if let error = result.error {
                    minimaxStatus = .invalid("\(error) — using defaults")
                } else {
                    minimaxStatus = .valid
                }
            }
        }
    }

    private func fetchORModels() {
        Task {
            let apiKey = conversation.loadAPIKey(for: .openRouter)
            let result = await ModelFetcher.fetchOpenRouterModels(apiKey: apiKey)
            await MainActor.run {
                if !result.models.isEmpty {
                    orModels = result.models
                    orStatus = .valid
                    if !result.models.contains(where: { $0.id == conversation.openRouterModel }) {
                        conversation.openRouterModel = result.models.first(where: { $0.id.contains("sonnet") })?.id ?? result.models[0].id
                    }
                } else if let error = result.error {
                    orStatus = .invalid("\(error) — using defaults")
                } else {
                    orStatus = .valid
                }
            }
        }
    }
}
