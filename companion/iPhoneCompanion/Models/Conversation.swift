import Foundation
import SwiftUI

enum AIBackend: String, CaseIterable {
    case claudeCode = "Claude Code"
    case claude = "Claude API"
    case openRouter = "OpenRouter"
    case minimax = "MiniMax"
    case ollama = "Ollama"
}

@MainActor
class Conversation: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    private var currentTask: Task<Void, Never>?

    @AppStorage("aiBackend") var aiBackend: AIBackend = .claude
    @AppStorage("claudeModel") var claudeModel: String = Constants.defaultClaudeModel
    @AppStorage("openRouterModel") var openRouterModel: String = Constants.defaultOpenRouterModel
    @AppStorage("openRouterVisionModel") var openRouterVisionModel: String = Constants.defaultOpenRouterVisionModel
    @AppStorage("minimaxModel") var minimaxModel: String = Constants.defaultMiniMaxModel
    @AppStorage("ollamaModel") var ollamaModel: String = Constants.defaultOllamaModel
    @AppStorage("ollamaURL") var ollamaURL: String = Constants.defaultOllamaURL
    @AppStorage("scriptsPath") var scriptsPath: String = Constants.defaultScriptsPath

    @Published var modelSupportsVision: Bool? // nil = unknown, checked on model change

    private var apiMessages: [APIMessage] = []
    private var toolOrchestrator: ToolOrchestrator?
    private var toolExecutor: ToolExecutor?
    private var cachedModelCapabilities: [String: ModelFetcher.ModelCapabilities] = [:]

    /// Factory for creating ToolExecutor instances. Injected for testability.
    private let toolExecutorFactory: (String) -> ToolExecutor

    init(toolExecutorFactory: ((String) -> ToolExecutor)? = nil) {
        self.toolExecutorFactory = toolExecutorFactory ?? { scriptsPath in
            ToolExecutor(scriptsPath: scriptsPath)
        }
    }

    private var currentToolOrchestrator: ToolOrchestrator {
        if let existing = toolOrchestrator {
            return existing
        }
        let orchestrator = ToolOrchestrator(toolExecutor: currentToolExecutor)
        toolOrchestrator = orchestrator
        return orchestrator
    }

    private var currentToolExecutor: ToolExecutor {
        if let existing = toolExecutor {
            return existing
        }
        let executor = toolExecutorFactory(scriptsPath)
        toolExecutor = executor
        return executor
    }

    func send(_ text: String) {
        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)

        apiMessages.append(APIMessage(role: "user", content: [.text(text)]))

        isProcessing = true

        currentTask = Task {
            // Check model capabilities on first message or if unknown
            if modelSupportsVision == nil {
                await checkModelCapabilities()
            }

            let orchestrator = currentToolOrchestrator
            let callbacks = ToolOrchestrator.LoopCallbacks(
                createService: { [weak self] in
                    await self?.createServiceAsync()
                },
                getBackend: { [weak self] in
                    self?.aiBackend ?? .claude
                },
                getApiMessages: { [weak self] in
                    self?.apiMessages ?? []
                },
                appendApiMessage: { [weak self] msg in
                    self?.apiMessages.append(msg)
                },
                appendChatMessage: { [weak self] msg in
                    self?.messages.append(msg)
                },
                updateChatMessage: { [weak self] idx, content in
                    self?.messages[idx].content = content
                },
                chatMessageCount: { [weak self] in
                    self?.messages.count ?? 0
                },
                needsVisionProxy: { [weak self] in
                    self?.needsVisionProxy ?? false
                },
                describeScreenshot: { [weak self] data in
                    await self?.describeScreenshot(imageData: data) ?? "[Vision unavailable]"
                },
                isCancelled: {
                    Task.isCancelled
                }
            )

            await orchestrator.runAILoop(callbacks: callbacks)
            isProcessing = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        messages.append(.assistant("Cancelled."))
    }

    func clearHistory() {
        messages.removeAll()
        apiMessages.removeAll()
    }

    /// Whole conversation as plain text for the "Copy chat" action.
    var transcript: String {
        messages.compactMap { message -> String? in
            let text = message.plainText
            guard !text.isEmpty else { return nil }
            let who = message.role == .user ? "You" : "Assistant"
            return "\(who): \(text)"
        }.joined(separator: "\n\n")
    }

    func resetToolExecutor() {
        toolExecutor = nil
        toolOrchestrator = nil
    }

    /// OAuth requires short model names (e.g. "claude-sonnet-4-6" not "claude-sonnet-4-6-20250514")
    private var oauthModelName: String {
        let model = claudeModel
        // Strip trailing -YYYYMMDD date suffix if present
        if let range = model.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(model[model.startIndex..<range.lowerBound])
        }
        return model
    }

    private func createServiceAsync() async -> AIService? {
        await AIServiceFactory.createServiceAsync(
            backend: aiBackend,
            claudeModel: claudeModel,
            oauthModelName: oauthModelName,
            openRouterModel: openRouterModel,
            minimaxModel: minimaxModel,
            ollamaModel: ollamaModel,
            ollamaURL: ollamaURL
        )
    }

    // MARK: - Vision Model Support

    func checkModelCapabilities() async {
        guard aiBackend == .openRouter else {
            // Claude API, Claude Code, and MiniMax always support vision
            modelSupportsVision = aiBackend != .ollama
            return
        }

        let modelId = openRouterModel
        if let cached = cachedModelCapabilities[modelId] {
            modelSupportsVision = cached.supportsVision
            return
        }

        if let caps = await ModelFetcher.fetchModelCapabilities(modelId: modelId) {
            cachedModelCapabilities[modelId] = caps
            modelSupportsVision = caps.supportsVision
        } else {
            modelSupportsVision = nil // unknown
        }
    }

    /// Describe a screenshot using the vision model when the main model doesn't support images
    private func describeScreenshot(imageData: Data) async -> String {
        let apiKey = loadAPIKey(for: .openRouter)
        guard aiBackend == .openRouter, !apiKey.isEmpty, !openRouterVisionModel.isEmpty else {
            return "[Screenshot taken - vision model not configured]"
        }

        guard let request = buildVisionRequest(imageData: imageData, apiKey: apiKey) else {
            return "[Vision model error: failed to build request]"
        }

        return await executeVisionRequest(request)
    }

    private func buildVisionRequest(imageData: Data, apiKey: String) -> URLRequest? {
        let base64 = imageData.base64EncodedString()
        let visionMessages: [[String: Any]] = [
            ["role": "user", "content": [
                // swiftlint:disable:next line_length
                ["type": "text", "text": "Describe this iPhone screenshot in detail. List all visible UI elements, text, buttons, icons, and their positions. Be thorough but concise."],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64)"]]
            ] as [Any]]
        ]

        let body: [String: Any] = [
            "model": openRouterVisionModel,
            "max_tokens": Constants.visionMaxTokens,
            "messages": visionMessages
        ]

        guard let url = URL(string: Constants.openRouterAPIURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            NSLog("[Companion] Failed to serialize vision request body: %@", error.localizedDescription)
            return nil
        }

        return request
    }

    private func executeVisionRequest(_ request: URLRequest) async -> String {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                // swiftlint:disable:next line_length
                return "[Vision model error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) \(errorBody.prefix(100))]"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                return "[Vision model: failed to parse response]"
            }

            return content
        } catch {
            return "[Vision model error: \(error.localizedDescription)]"
        }
    }

    /// Whether screenshots need to be described via a separate vision model
    private var needsVisionProxy: Bool {
        aiBackend == .openRouter && modelSupportsVision == false
    }

    // MARK: - API Key Management (facade over KeychainHelper)

    private static let keychainKeys: [AIBackend: String] = [
        .claude: "claude-api-key",
        .openRouter: "openrouter-api-key",
        .minimax: "minimax-api-key"
    ]

    @Published private var cachedAPIKeys: [AIBackend: String] = [:]

    func loadAPIKey(for backend: AIBackend) -> String {
        if let cached = cachedAPIKeys[backend] { return cached }
        guard let keychainKey = Self.keychainKeys[backend] else { return "" }
        let value = KeychainHelper.load(key: keychainKey) ?? ""
        cachedAPIKeys[backend] = value
        return value
    }

    func saveAPIKey(_ value: String, for backend: AIBackend) {
        cachedAPIKeys[backend] = value
        guard let keychainKey = Self.keychainKeys[backend], !value.isEmpty else { return }
        KeychainHelper.save(key: keychainKey, value: value)
    }

    var hasAPIKey: Bool {
        switch aiBackend {
        case .claudeCode: return ClaudeCodeAuthHelper.isAvailable
        case .claude: return !loadAPIKey(for: .claude).isEmpty
        case .openRouter: return !loadAPIKey(for: .openRouter).isEmpty
        case .minimax: return !loadAPIKey(for: .minimax).isEmpty
        case .ollama: return true
        }
    }

    func loadAllAPIKeys() {
        for backend in Self.keychainKeys.keys {
            _ = loadAPIKey(for: backend)
        }
    }
}

extension AIBackend: RawRepresentable {}
