import Foundation

class ClaudeAPIService: ToolCapableAIService, VisionCapableAIService {
    let apiKey: String
    let model: String
    let useOAuth: Bool

    init(apiKey: String, model: String = Constants.defaultClaudeModel, useOAuth: Bool = false) {
        self.apiKey = apiKey
        self.model = model
        self.useOAuth = useOAuth
    }

    func send(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) async throws -> AsyncStream<StreamEvent> {
        let body = buildRequestBody(messages: messages, tools: tools, systemPrompt: systemPrompt)

        var request = URLRequest(url: URL(string: Constants.claudeAPIURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if useOAuth {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }

        return AsyncStream { continuation in
            Task {
                var currentToolId = ""
                var currentToolName = ""
                var currentToolInputJSON = ""

                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        let eventType = event["type"] as? String ?? ""

                        switch eventType {
                        case "content_block_start":
                            if let contentBlock = event["content_block"] as? [String: Any],
                               contentBlock["type"] as? String == "tool_use" {
                                currentToolId = contentBlock["id"] as? String ?? ""
                                currentToolName = contentBlock["name"] as? String ?? ""
                                currentToolInputJSON = ""
                            }

                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any] {
                                let deltaType = delta["type"] as? String ?? ""
                                if deltaType == "text_delta", let text = delta["text"] as? String {
                                    continuation.yield(.textDelta(text))
                                } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                                    currentToolInputJSON += partial
                                }
                            }

                        case "content_block_stop":
                            if !currentToolId.isEmpty {
                                var input: [String: Any] = [:]
                                if let data = currentToolInputJSON.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    input = parsed
                                }
                                continuation.yield(.toolUse(id: currentToolId, name: currentToolName, input: input))
                                currentToolId = ""
                                currentToolName = ""
                                currentToolInputJSON = ""
                            }

                        case "message_delta":
                            if let delta = event["delta"] as? [String: Any],
                               let stopReason = delta["stop_reason"] as? String {
                                continuation.yield(.done(stopReason: stopReason))
                            }

                        case "error":
                            let errorMsg = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                            continuation.yield(.error(errorMsg))

                        default:
                            break
                        }
                    }
                } catch {
                    NSLog("[Companion] Claude SSE stream error: %@", error.localizedDescription)
                    continuation.yield(.error("Stream error: \(error.localizedDescription)"))
                }

                continuation.finish()
            }
        }
    }

    private func buildRequestBody(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) -> [String: Any] {
        let apiMessages = messages.map { msg -> [String: Any] in
            [
                "role": msg.role,
                "content": msg.content.map { $0.toDict() },
            ]
        }

        return [
            "model": model,
            "max_tokens": Constants.maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": apiMessages,
            "tools": tools,
        ]
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from API"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}
