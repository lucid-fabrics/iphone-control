import Foundation

/// Factory responsible for creating AI service instances based on backend configuration.
enum AIServiceFactory {
    /// Create an AI service synchronously (for backends that don't need async token refresh).
    static func createService(
        backend: AIBackend,
        claudeModel: String,
        oauthModelName: String,
        openRouterModel: String,
        minimaxModel: String,
        ollamaModel: String,
        ollamaURL: String
    ) -> AIService? {
        switch backend {
        case .claudeCode:
            guard let creds = ClaudeCodeAuthHelper.loadCredentials(),
                  creds.expiresAt.timeIntervalSinceNow > 0
            else { return nil }
            return ClaudeAPIService(apiKey: creds.accessToken, model: oauthModelName, useOAuth: true)
        case .claude:
            guard let apiKey = KeychainHelper.load(key: "claude-api-key"), !apiKey.isEmpty else {
                return nil
            }
            return ClaudeAPIService(apiKey: apiKey, model: claudeModel)
        case .openRouter:
            guard let apiKey = KeychainHelper.load(key: "openrouter-api-key"), !apiKey.isEmpty else {
                return nil
            }
            return OpenRouterService(apiKey: apiKey, model: openRouterModel)
        case .minimax:
            guard let apiKey = KeychainHelper.load(key: "minimax-api-key"), !apiKey.isEmpty else {
                return nil
            }
            return MiniMaxService(apiKey: apiKey, model: minimaxModel)
        case .ollama:
            return OllamaService(baseURL: ollamaURL, model: ollamaModel)
        }
    }

    /// Create an AI service with async token refresh support (for Claude Code OAuth).
    static func createServiceAsync(
        backend: AIBackend,
        claudeModel: String,
        oauthModelName: String,
        openRouterModel: String,
        minimaxModel: String,
        ollamaModel: String,
        ollamaURL: String
    ) async -> AIService? {
        if case .claudeCode = backend {
            guard let token = await ClaudeCodeAuthHelper.getValidToken() else { return nil }
            return ClaudeAPIService(apiKey: token, model: oauthModelName, useOAuth: true)
        }
        return createService(
            backend: backend,
            claudeModel: claudeModel,
            oauthModelName: oauthModelName,
            openRouterModel: openRouterModel,
            minimaxModel: minimaxModel,
            ollamaModel: ollamaModel,
            ollamaURL: ollamaURL
        )
    }
}
