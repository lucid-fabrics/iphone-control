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
                // Key valid but no access to /v1/models — validate via messages endpoint
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
            models.sort { a, b in
                let tierA = modelTier(a.id)
                let tierB = modelTier(b.id)
                if tierA != tierB { return tierA < tierB }
                return a.id > b.id
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

        // Minimal request — will fail with 400 (bad request) if key is valid but request is incomplete
        // Will fail with 401 if key is invalid
        let body: [String: Any] = [
            "model": "claude-haiku-3-5-20241022",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
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
            models.sort { a, b in
                let aIsAnthropic = a.id.hasPrefix("anthropic/")
                let bIsAnthropic = b.id.hasPrefix("anthropic/")
                if aIsAnthropic != bIsAnthropic { return aIsAnthropic }
                return a.name < b.name
            }

            return (models, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - MiniMax Models

    /// MiniMax doesn't expose a /v1/models endpoint — validate the key via a minimal
    /// chat request, then return the known static model list.
    static func fetchMinimaxModels(apiKey: String) async -> (models: [ClaudeModel], error: String?) {
        guard !apiKey.isEmpty else { return ([], "No API key") }

        var request = URLRequest(url: URL(string: Constants.minimaxAPIURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "MiniMax-Text-01",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ([], "No response")
            }
            if httpResponse.statusCode == 401 {
                return ([], "Invalid API key")
            }
            // 200 or 400 (bad request) both mean the key is valid
        } catch {
            return ([], error.localizedDescription)
        }

        let models = Constants.fallbackMiniMaxModels.map { ClaudeModel(id: $0.id, name: $0.name) }
        return (models, nil)
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

            // Find our model — handle :free suffix matching
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
