import Foundation

struct ClaudeModel: Identifiable, Hashable {
    let id: String
    let name: String
}

enum ModelFetcher {
    static func fetchModels(apiKey: String) async -> (models: [ClaudeModel], error: String?) {
        guard !apiKey.isEmpty else { return ([], "No API key") }

        var request = URLRequest(url: URL(string: "\(Constants.claudeModelsURL)?limit=1000")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ([], "No response")
            }

            if httpResponse.statusCode == 401 {
                return ([], "Invalid API key")
            }

            if httpResponse.statusCode == 403 {
                // Key valid but no access to /v1/models - validate via messages endpoint
                let valid = await validateKey(apiKey: apiKey)
                return ([], valid ? nil : "Invalid API key")
            }

            if httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ([], "HTTP \(httpResponse.statusCode): \(body.prefix(100))")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["data"] as? [[String: Any]]
            else {
                return ([], "Failed to parse response")
            }

            var models: [ClaudeModel] = []
            for model in modelsArray {
                guard let id = model["id"] as? String, id.hasPrefix("claude-") else { continue }
                let displayName = model["display_name"] as? String ?? formatModelName(id)
                models.append(ClaudeModel(id: id, name: displayName))
            }

            // Sort: opus > sonnet > haiku
            models.sort { lhs, rhs in
                let tierA = modelTier(lhs.id)
                let tierB = modelTier(rhs.id)
                if tierA != tierB { return tierA < tierB }
                return lhs.id > rhs.id
            }

            return (models, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    static func validateKey(apiKey: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.claudeAPIURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Minimal request - will fail with 400 (bad request) if key is valid but request is incomplete
        // Will fail with 401 if key is invalid
        let body: [String: Any] = [
            "model": "claude-haiku-3-5-20241022",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            // 200 = valid, 400 = valid key but bad request, 401 = invalid key
            return httpResponse.statusCode != 401
        } catch {
            return false
        }
    }

    // MARK: - OpenRouter Models

    // Long provider-support OR-chain keeps this just over the limit; splitting it out
    // would not make it clearer. Pre-existing, unrelated to model detection.
    // swiftlint:disable:next cyclomatic_complexity
    static func fetchOpenRouterModels(apiKey: String) async -> (models: [ClaudeModel], error: String?) {
        guard !apiKey.isEmpty else { return ([], "No API key") }

        var request = URLRequest(url: URL(string: Constants.openRouterModelsURL)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ([], "No response")
            }

            if httpResponse.statusCode == 401 {
                return ([], "Invalid API key")
            }

            if httpResponse.statusCode != 200 {
                return ([], "HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["data"] as? [[String: Any]]
            else {
                return ([], "Failed to parse response")
            }

            // Filter to models that support tool use (function calling)
            var models: [ClaudeModel] = []
            for model in modelsArray {
                guard let id = model["id"] as? String,
                      let name = model["name"] as? String
                else { continue }

                // Only include models likely to support tool use
                let supported = id.contains("claude") ||
                    id.contains("gpt-4") ||
                    id.contains("gemini") ||
                    id.contains("llama") ||
                    id.contains("mistral") ||
                    id.contains("deepseek") ||
                    id.contains("qwen")

                guard supported else { continue }

                // Skip very old/deprecated models
                if id.contains("claude-1") || id.contains("claude-2") { continue }
                if id.contains("gpt-3.5") { continue }

                models.append(ClaudeModel(id: id, name: name))
            }

            // Sort: anthropic first, then others
            models.sort { lhs, rhs in
                let aIsAnthropic = lhs.id.hasPrefix("anthropic/")
                let bIsAnthropic = rhs.id.hasPrefix("anthropic/")
                if aIsAnthropic != bIsAnthropic { return aIsAnthropic }
                return lhs.name < rhs.name
            }

            return (models, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - MiniMax Models

    /// Live-detect MiniMax models from the OpenAI-compatible GET /v1/models endpoint,
    /// so newly released ids (M3, M4, ...) appear automatically. Falls back to the
    /// static list only if the endpoint is unreachable or returns nothing usable.
    static func fetchMinimaxModels(apiKey: String) async -> (models: [ClaudeModel], error: String?) {
        guard !apiKey.isEmpty else { return ([], "No API key") }

        var request = URLRequest(url: URL(string: Constants.minimaxModelsURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (fallbackMinimaxModels, "No response, using defaults")
            }
            if httpResponse.statusCode == 401 {
                return ([], "Invalid API key")
            }
            guard httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["data"] as? [[String: Any]]
            else {
                // Older accounts / regions may still 404 this endpoint.
                return (fallbackMinimaxModels, "Model list unavailable, using defaults")
            }

            // Newest first (by created timestamp). The id IS the value sent to the
            // chat endpoint; derive a readable name from it. Drop embedding models.
            let models = entries
                .compactMap { entry -> (id: String, created: Int)? in
                    guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
                    return (id, entry["created"] as? Int ?? 0)
                }
                .filter { !$0.id.lowercased().contains("embo") }
                .sorted { $0.created > $1.created }
                .map { ClaudeModel(id: $0.id, name: minimaxDisplayName(for: $0.id)) }

            return models.isEmpty ? (fallbackMinimaxModels, nil) : (models, nil)
        } catch {
            return (fallbackMinimaxModels, error.localizedDescription)
        }
    }

    private static var fallbackMinimaxModels: [ClaudeModel] {
        Constants.fallbackMiniMaxModels.map { ClaudeModel(id: $0.id, name: $0.name) }
    }

    /// "MiniMax-M3" -> "MiniMax M3", "MiniMax-Text-01" -> "MiniMax Text 01".
    private static func minimaxDisplayName(for identifier: String) -> String {
        identifier.replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - Model Capabilities

    struct ModelCapabilities {
        let supportsVision: Bool
        let supportsTools: Bool
    }

    static func fetchModelCapabilities(modelId: String) async -> ModelCapabilities? {
        guard let url = URL(string: Constants.openRouterModelsURL) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["data"] as? [[String: Any]]
            else { return nil }

            // Find our model - handle :free suffix matching
            let baseId = modelId.replacingOccurrences(of: ":free", with: "")
            guard let model = modelsArray.first(where: { ($0["id"] as? String) == modelId })
                    ?? modelsArray.first(where: { ($0["id"] as? String) == baseId })
            else { return nil }

            let arch = model["architecture"] as? [String: Any] ?? [:]
            let inputModalities = arch["input_modalities"] as? [String] ?? []
            let supportedParams = model["supported_parameters"] as? [String] ?? []

            return ModelCapabilities(
                supportsVision: inputModalities.contains("image"),
                supportsTools: supportedParams.contains("tools")
            )
        } catch {
            return nil
        }
    }

    private static func formatModelName(_ id: String) -> String {
        var name = id.replacingOccurrences(of: "claude-", with: "")
        let parts = name.split(separator: "-")
        var filtered = parts.filter { part in
            !(part.count >= 8 && part.allSatisfy(\.isNumber))
        }
        guard !filtered.isEmpty else { return id }
        let family = String(filtered.removeFirst()).capitalized
        let version = filtered.joined(separator: ".")
        return version.isEmpty ? family : "\(family) \(version)"
    }

    private static func modelTier(_ id: String) -> Int {
        if id.contains("opus") { return 0 }
        if id.contains("sonnet") { return 1 }
        if id.contains("haiku") { return 2 }
        return 3
    }
}
