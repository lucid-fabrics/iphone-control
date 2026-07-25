import Foundation

class MiniMaxService: ToolCapableAIService, VisionCapableAIService {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "MiniMax-M2.7") {
        self.apiKey = apiKey
        self.model = model
    }

    func send(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) async throws -> AsyncStream<StreamEvent> {
        let mmMessages = buildMessages(messages: messages, systemPrompt: systemPrompt)
        let mmTools = buildTools(tools: tools)

        var body: [String: Any] = [
            "model": model,
            "messages": mmMessages,
            "stream": true,
            "max_tokens": Constants.maxTokens,
        ]

        if !mmTools.isEmpty {
            body["tools"] = mmTools
        }

        var request = URLRequest(url: URL(string: Constants.minimaxAPIURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line + "\n"
            }
            NSLog("[Companion] MiniMax error: status=%d, body=%@", httpResponse.statusCode, errorBody)
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }

        return AsyncStream { continuation in
            Task {
                // Accumulate streaming tool_calls by index (OpenAI v1 streaming format)
                var toolCallsById: [Int: (id: String, name: String, arguments: String)] = [:]

                do {
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              line.hasPrefix("data: "),
                              let data = line.dropFirst(6).data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let error = event["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            continuation.yield(.error(message))
                            continue
                        }

                        guard let choices = event["choices"] as? [[String: Any]],
                              let choice = choices.first
                        else { continue }

                        if let delta = choice["delta"] as? [String: Any] {
                            // Text content
                            if let content = delta["content"] as? String, !content.isEmpty {
                                continuation.yield(.textDelta(content))
                            }

                            // OpenAI v1 tool_calls streaming format
                            if let toolCallChunks = delta["tool_calls"] as? [[String: Any]] {
                                for chunk in toolCallChunks {
                                    let index = chunk["index"] as? Int ?? 0
                                    let chunkId = chunk["id"] as? String ?? ""
                                    let fn = chunk["function"] as? [String: Any] ?? [:]
                                    let chunkName = fn["name"] as? String ?? ""
                                    let chunkArgs = fn["arguments"] as? String ?? ""

                                    if var existing = toolCallsById[index] {
                                        existing.arguments += chunkArgs
                                        if !chunkId.isEmpty { existing.id = chunkId }
                                        if !chunkName.isEmpty { existing.name = chunkName }
                                        toolCallsById[index] = existing
                                    } else {
                                        toolCallsById[index] = (id: chunkId, name: chunkName, arguments: chunkArgs)
                                    }
                                }
                            }

                            // Legacy function_call format (older MiniMax models)
                            if let functionCall = delta["function_call"] as? [String: Any],
                               let name = functionCall["name"] as? String {
                                let args = functionCall["arguments"] as? String ?? "{}"
                                var argsDict: [String: Any] = [:]
                                if let argsData = args.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                                    argsDict = parsed
                                }
                                let id = "mm-\(UUID().uuidString.prefix(8))"
                                continuation.yield(.toolUse(id: id, name: name, input: argsDict))
                            }
                        }

                        let finishReason = choice["finish_reason"] as? String
                        if let reason = finishReason {
                            // Flush accumulated tool_calls
                            let hadToolCalls = !toolCallsById.isEmpty
                            for index in toolCallsById.keys.sorted() {
                                let call = toolCallsById[index]!
                                guard !call.name.isEmpty else { continue }
                                var argsDict: [String: Any] = [:]
                                if let argsData = call.arguments.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                                    argsDict = parsed
                                }
                                let id = call.id.isEmpty ? "mm-\(UUID().uuidString.prefix(8))" : call.id
                                continuation.yield(.toolUse(id: id, name: call.name, input: argsDict))
                            }
                            toolCallsById.removeAll()

                            let isToolUse = reason == "tool_calls" || hadToolCalls
                            continuation.yield(.done(stopReason: isToolUse ? "tool_use" : "stop"))
                        }
                    }
                } catch {
                    NSLog("[Companion] MiniMax SSE stream error: %@", error.localizedDescription)
                    continuation.yield(.error("Stream error: \(error.localizedDescription)"))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Message Building

    /// Build OpenAI-compatible messages array.
    /// Tool calls → assistant message with `tool_calls` field.
    /// Tool results → separate `role: "tool"` messages.
    private func buildMessages(messages: [APIMessage], systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
        ]

        for msg in messages {
            // Collect text, tool calls, and tool results separately
            var textParts: [String] = []
            var toolCalls: [[String: Any]] = []
            var toolResults: [[String: Any]] = []

            for block in msg.content {
                switch block {
                case .text(let text):
                    textParts.append(text)

                case .image:
                    break // handled in buildUserContent via msg.content re-scan

                case .toolUse(let id, let name, let input):
                    let inputJson = (try? JSONSerialization.data(withJSONObject: input))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    toolCalls.append([
                        "id": id,
                        "type": "function",
                        "function": ["name": name, "arguments": inputJson],
                    ])

                case .toolResult(let toolUseId, let subContent, _):
                    var resultText = ""
                    for sub in subContent {
                        if case .text(let t) = sub { resultText += t }
                    }
                    toolResults.append([
                        "role": "tool",
                        "tool_call_id": toolUseId,
                        "content": resultText,
                    ])
                }
            }

            if msg.role == "user" {
                // Tool results become separate role:tool messages
                result.append(contentsOf: toolResults)

                // Regular user text (if any)
                if !textParts.isEmpty || toolResults.isEmpty {
                    let content = buildUserContent(textParts: textParts, msg: msg)
                    result.append(["role": "user", "content": content])
                }
            } else {
                // Assistant message: text + tool_calls
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if !textParts.isEmpty {
                    assistantMsg["content"] = textParts.joined()
                } else {
                    assistantMsg["content"] = NSNull()
                }
                if !toolCalls.isEmpty {
                    assistantMsg["tool_calls"] = toolCalls
                }
                result.append(assistantMsg)
            }
        }

        return result
    }

    private func buildUserContent(textParts: [String], msg: APIMessage) -> Any {
        // Check if there are images
        let hasImages = msg.content.contains { if case .image = $0 { return true }; return false }

        if hasImages {
            var blocks: [[String: Any]] = []
            for part in textParts {
                blocks.append(["type": "text", "text": part])
            }
            for block in msg.content {
                if case .image(let base64, let mediaType) = block {
                    blocks.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(mediaType);base64,\(base64)"],
                    ])
                }
            }
            return blocks
        }

        return textParts.joined()
    }

    // MARK: - Tool Building

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
                ],
            ]
        }
    }
}
