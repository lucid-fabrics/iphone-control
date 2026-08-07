import SwiftUI

// Pre-existing large settings view (one section per provider). Splitting it is a
// separate refactor; the length rules are relaxed here rather than in shared config.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct SettingsView: View {
    @EnvironmentObject var conversation: Conversation
    @State private var showingClaudeKey = false
    @State private var showingORKey = false
    @State private var showingMinimaxKey = false
    @State private var claudeModels: [ClaudeModel] = []
    @State private var orModels: [ClaudeModel] = []
    @State private var minimaxModels: [ClaudeModel] = []
    @State private var claudeStatus: SettingsStatus = .idle
    @State private var orStatus: SettingsStatus = .idle
    @State private var minimaxStatus: SettingsStatus = .idle
    @State private var orVisionStatus: SettingsStatus = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Backend picker
                settingsSection("AI Backend") {
                    Picker("Backend", selection: $conversation.aiBackend) {
                        ForEach(AIBackend.allCases, id: \.self) { backend in
                            Text(backend.rawValue).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Claude Code
                if conversation.aiBackend == .claudeCode {
                    claudeCodeSection
                }

                // Claude
                if conversation.aiBackend == .claude {
                    claudeAPISection
                }

                // OpenRouter
                if conversation.aiBackend == .openRouter {
                    openRouterSection
                }

                // MiniMax
                if conversation.aiBackend == .minimax {
                    minimaxSection
                }

                // Ollama
                if conversation.aiBackend == .ollama {
                    ollamaSection
                }

                // Scripts path
                settingsSection("Scripts") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Path to iphone-control", text: $conversation.scriptsPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            settingsButton("Browse") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    conversation.scriptsPath = url.path
                                    conversation.resetToolExecutor()
                                }
                            }
                        }
                        Text("Path to the iphone-control repo with shell scripts")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(18)
        }
        .onAppear {
            conversation.loadAllAPIKeys()
        }
    }

    // MARK: - Provider Sections

    private var claudeCodeSection: some View {
        settingsSection("Claude Code") {
            VStack(alignment: .leading, spacing: 10) {
                if let creds = ClaudeCodeAuthHelper.loadCredentials() {
                    let isValid = creds.expiresAt.timeIntervalSinceNow > 0
                    HStack(spacing: 8) {
                        Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(isValid ? Theme.statusLive : Theme.statusBusy)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isValid ? "Authenticated" : "Token Expired")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Subscription: \(creds.subscriptionType)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !isValid {
                        Text("Run `claude` in terminal to re-authenticate")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                        Text("Credentials not found")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text("Run `claude` in terminal to authenticate")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. claude-sonnet-4-6", text: $conversation.claudeModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text("OAuth requires short model names (no date suffix)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private var claudeAPISection: some View {
        settingsSection("Claude API") {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .claude) },
                        set: { conversation.saveAPIKey($0, for: .claude) }
                    ),
                    showing: $showingClaudeKey,
                    placeholder: "sk-ant-api03-..."
                )
                HStack {
                    settingsButton("Save & Detect Models") {
                        conversation.saveAPIKey(conversation.loadAPIKey(for: .claude), for: .claude)
                        claudeStatus = .validating
                        fetchClaudeModels()
                    }
                    .disabled(conversation.loadAPIKey(for: .claude).isEmpty)
                    statusView(claudeStatus)
                }

                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $conversation.claudeModel) {
                    if claudeModels.isEmpty {
                        ForEach(Constants.fallbackClaudeModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    } else {
                        ForEach(claudeModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var openRouterSection: some View {
        settingsSection("OpenRouter") {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .openRouter) },
                        set: { conversation.saveAPIKey($0, for: .openRouter) }
                    ),
                    showing: $showingORKey,
                    placeholder: "sk-or-..."
                )
                HStack {
                    settingsButton("Save Key") {
                        orStatus = .valid
                    }
                    .disabled(conversation.loadAPIKey(for: .openRouter).isEmpty)
                    statusView(orStatus)
                }

                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. anthropic/claude-sonnet-4.6", text: $conversation.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: conversation.openRouterModel) { _, _ in
                        conversation.modelSupportsVision = nil
                        orVisionStatus = .idle
                    }

                HStack {
                    settingsButton("Check Model") {
                        orVisionStatus = .validating
                        Task {
                            await conversation.checkModelCapabilities()
                            if conversation.modelSupportsVision == true {
                                orVisionStatus = .valid
                            } else if conversation.modelSupportsVision == false {
                                orVisionStatus = .invalid("No vision support")
                            } else {
                                orVisionStatus = .invalid("Could not detect")
                            }
                        }
                    }
                    statusView(orVisionStatus)
                }

                if conversation.modelSupportsVision == false {
                    Divider()
                    Text("Vision Model")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Screenshots described by this model")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    TextField("e.g. google/gemma-3-12b-it:free", text: $conversation.openRouterVisionModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text("openrouter.ai/keys")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.quaternary)
            }
        }
    }

    private var minimaxSection: some View {
        settingsSection("MiniMax") {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                apiKeyField(
                    key: Binding(
                        get: { conversation.loadAPIKey(for: .minimax) },
                        set: { conversation.saveAPIKey($0, for: .minimax) }
                    ),
                    showing: $showingMinimaxKey,
                    placeholder: "sk-cp-..."
                )
                HStack {
                    settingsButton("Save & Detect Models") {
                        conversation.saveAPIKey(conversation.loadAPIKey(for: .minimax), for: .minimax)
                        minimaxStatus = .validating
                        fetchMinimaxModels()
                    }
                    .disabled(conversation.loadAPIKey(for: .minimax).isEmpty)
                    statusView(minimaxStatus)
                }

                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $conversation.minimaxModel) {
                    if minimaxModels.isEmpty {
                        ForEach(Constants.fallbackMiniMaxModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    } else {
                        ForEach(minimaxModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                }
                .labelsHidden()

                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text("minimax.io")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.quaternary)
            }
        }
    }

    private var ollamaSection: some View {
        settingsSection("Ollama") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("llama3.1", text: $conversation.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                Text("URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("http://localhost:11434", text: $conversation.ollamaURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Settings Helpers

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.raised.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Theme.hairline, lineWidth: 0.5)
                        )
                )
        }
    }

    @ViewBuilder
    private func settingsButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.accent.opacity(0.1))
                )
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func apiKeyField(key: Binding<String>, showing: Binding<Bool>, placeholder: String) -> some View {
        HStack {
            if showing.wrappedValue {
                TextField(placeholder, text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                SecureField(placeholder, text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            Button(showing.wrappedValue ? "Hide" : "Show") {
                showing.wrappedValue.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private func statusView(_ status: SettingsStatus) -> some View {
        switch status {
        case .idle: EmptyView()
        case .validating:
            ProgressView().scaleEffect(0.6)
        case .valid:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("Saved")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.green)
        case .invalid(let msg):
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(msg)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Data Fetching

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
                    minimaxStatus = .invalid("\(error) using defaults")
                } else {
                    minimaxStatus = .valid
                }
            }
        }
    }

    private func fetchClaudeModels() {
        Task {
            let apiKey = conversation.loadAPIKey(for: .claude)
            let result = await ModelFetcher.fetchModels(apiKey: apiKey)
            await MainActor.run {
                if !result.models.isEmpty {
                    claudeModels = result.models
                    claudeStatus = .valid
                    if !result.models.contains(where: { $0.id == conversation.claudeModel }) {
                        let sonnet = result.models.first(where: { $0.id.contains("sonnet") })?.id
                        conversation.claudeModel = sonnet ?? result.models[0].id
                    }
                } else if let error = result.error {
                    claudeStatus = .invalid("\(error)")
                } else {
                    claudeStatus = .valid
                }
            }
        }
    }
}

enum SettingsStatus: Equatable {
    case idle, validating, valid, invalid(String)
}
