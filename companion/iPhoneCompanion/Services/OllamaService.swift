import Foundation

class OllamaService: ToolCapableAIService {
    let baseURL: String
    let model: String

    init(baseURL: String = Constants.defaultOllamaURL, model: String = Constants.defaultOllamaModel) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.model = model
    }

    func send(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) async throws -> AsyncStream<StreamEvent> {
        let ollamaMessages = buildMessages(messages: messages, systemPrompt: systemPrompt)
        let ollamaTools = buildTools(tools: tools)

        let body: [String: Any] = [
            "model": model,
            "messages": ollamaMessages,
            "tools": ollamaTools,
            "stream": true,
        ]

        var request = URLRequest(url: URL(string: "\(baseURL)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return AsyncStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let message = event["message"] as? [String: Any] {
                            // Text content
                            if let content = message["content"] as? String, !content.isEmpty {
                                continuation.yield(.textDelta(content))
                            }

                            // Tool calls
                            if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                                for call in toolCalls {
                                    if let function = call["function"] as? [String: Any],
                                       let name = function["name"] as? String {
                                        let args = function["arguments"] as? [String: Any] ?? [:]
                                        let id = "ollama-\(UUID().uuidString.prefix(8))"
                                        continuation.yield(.toolUse(id: id, name: name, input: args))
                                    }
                                }
                            }
                        }

                        if event["done"] as? Bool == true {
                            let hasTools = (event["message"] as? [String: Any])?["tool_calls"] != nil
                            continuation.yield(.done(stopReason: hasTools ? "tool_use" : "end_turn"))
                        }
                    }
                } catch {
                    NSLog("[Companion] Ollama SSE stream error: %@", error.localizedDescription)
                    continuation.yield(.error("Stream error: \(error.localizedDescription)"))
                }
                continuation.finish()
            }
        }
    }

    private func buildMessages(messages: [APIMessage], systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
        ]

        for msg in messages {
            var content = ""
            for block in msg.content {
                switch block {
                case .text(let text): content += text
                case .toolResult(_, let subContent, _):
                    for sub in subContent {
                        if case .text(let t) = sub { content += t }
                    }
                default: break
                }
            }
            if !content.isEmpty {
                result.append(["role": msg.role == "assistant" ? "assistant" : "user", "content": content])
            }
        }

        return result
    }

    private func buildTools(tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool -> [String: Any]? in
            guard let name = tool["name"] as? String,
                  let description = tool["description"] as? String,
                  let inputSchema = tool["input_schema"] as? [String: Any]
            else { return nil }

            return [
                "type": "function",
                "function": [
                    "name": name,
                    "description": description,
                    "parameters": inputSchema,
                ] as [String: Any],
            ]
        }
    }
}
