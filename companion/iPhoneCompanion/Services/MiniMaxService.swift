import Foundation

class MiniMaxService: ToolCapableAIService, VisionCapableAIService {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "MiniMax-M2.7") {
        self.apiKey = apiKey
        self.model = model
    }

    // Pre-existing single-pass SSE reader; splitting it would not make it clearer.
    // swiftlint:disable:next cyclomatic_complexity function_body_length line_length
    func send(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) async throws -> AsyncStream<StreamEvent> {
        let mmMessages = buildMessages(messages: messages, systemPrompt: systemPrompt)
        let mmTools = buildTools(tools: tools)

        var body: [String: Any] = [
            "model": model,
            "messages": mmMessages,
            "stream": true,
            "max_tokens": Constants.maxTokens
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
                var toolCallsById: [Int: PartialToolCall] = [:]
                // MiniMax M2/M3 are reasoning models: they wrap chain-of-thought in
                // inline <think>...</think> inside the content stream. Strip it so only
                // the user-facing answer reaches the UI and the stored history.
                let stripper = ThinkStripper()

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
                            // Text content (with <think>...</think> reasoning removed)
                            if let content = delta["content"] as? String, !content.isEmpty {
                                let visible = stripper.feed(content)
                                if !visible.isEmpty { continuation.yield(.textDelta(visible)) }
                            }

                            // OpenAI v1 tool_calls streaming format
                            if let toolCallChunks = delta["tool_calls"] as? [[String: Any]] {
                                for chunk in toolCallChunks {
                                    let index = chunk["index"] as? Int ?? 0
                                    let chunkId = chunk["id"] as? String ?? ""
                                    let funcObj = chunk["function"] as? [String: Any] ?? [:]
                                    let chunkName = funcObj["name"] as? String ?? ""
                                    let chunkArgs = funcObj["arguments"] as? String ?? ""

                                    if var existing = toolCallsById[index] {
                                        existing.arguments += chunkArgs
                                        if !chunkId.isEmpty { existing.id = chunkId }
                                        if !chunkName.isEmpty { existing.name = chunkName }
                                        toolCallsById[index] = existing
                                    } else {
                                        toolCallsById[index] = PartialToolCall(
                                            id: chunkId, name: chunkName, arguments: chunkArgs)
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

                            // Flush any text held back for partial-tag detection.
                            let tail = stripper.flush()
                            if !tail.isEmpty { continuation.yield(.textDelta(tail)) }

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

    // Pre-existing builder; the role/tool-call fan-out keeps it just over the limits.
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Build OpenAI-compatible messages array.
    /// Tool calls → assistant message with `tool_calls` field.
    /// Tool results → separate `role: "tool"` messages.
    private func buildMessages(messages: [APIMessage], systemPrompt: String) -> [[String: Any]] {
        var result: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in messages {
            // Collect text, tool calls, and tool results separately
            var textParts: [String] = []
            var toolCalls: [[String: Any]] = []
            var toolResults: [[String: Any]] = []
            var toolResultImages: [[String: Any]] = []

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
                        "function": ["name": name, "arguments": inputJson]
                    ])

                case .toolResult(let toolUseId, let subContent, _):
                    var resultText = ""
                    for sub in subContent {
                        switch sub {
                        case .text(let piece):
                            resultText += piece
                        case .image(let base64, let mediaType):
                            // role:"tool" content is text-only in the OpenAI format;
                            // silently dropping these left the model driving BLIND.
                            // Ferry screenshots in a follow-up user message instead.
                            toolResultImages.append([
                                "type": "image_url",
                                "image_url": ["url": "data:\(mediaType);base64,\(base64)"]
                            ])
                        default:
                            break
                        }
                    }
                    toolResults.append([
                        "role": "tool",
                        "tool_call_id": toolUseId,
                        "content": resultText
                    ])
                }
            }

            if msg.role == "user" {
                // Tool results become separate role:tool messages
                result.append(contentsOf: toolResults)

                // Screenshots from tool results ride in a user message right after
                // (tool messages cannot carry images in this API format).
                if !toolResultImages.isEmpty {
                    var blocks: [[String: Any]] = [
                        ["type": "text", "text": "Screenshot from the tool result above:"]
                    ]
                    blocks.append(contentsOf: toolResultImages)
                    result.append(["role": "user", "content": blocks])
                }

                // Regular user text (if any)
                if !textParts.isEmpty || (toolResults.isEmpty && toolResultImages.isEmpty) {
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
    // swiftlint:enable cyclomatic_complexity function_body_length

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
                        "image_url": ["url": "data:\(mediaType);base64,\(base64)"]
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
                    "parameters": inputSchema
                ]
            ]
        }
    }
}

/// Accumulated OpenAI-style streaming tool call (id/name/arguments arrive in pieces).
private struct PartialToolCall {
    var id: String
    var name: String
    var arguments: String
}

/// Removes inline `<think>...</think>` chain-of-thought from a streamed token feed.
/// Reasoning models (MiniMax M2/M3) emit their thinking this way; only the answer
/// should reach the UI. Tags split across chunks are handled by holding back a short
/// tail until it can be resolved.
final class ThinkStripper {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"
    private static let maxTagLength = 8   // count("</think>")

    private var buffer = ""
    private var insideThink = false

    /// Feed one content delta; returns the portion safe to display now.
    func feed(_ chunk: String) -> String {
        buffer += chunk
        var output = ""
        consumeTags(into: &output)

        if insideThink {
            // Discard reasoning text, keeping only a possible partial closing tag.
            if buffer.count > Self.maxTagLength - 1 {
                buffer = String(buffer.suffix(Self.maxTagLength - 1))
            }
        } else {
            // Emit everything except a possible partial opening tag.
            let hold = Self.maxTagLength - 1
            if buffer.count > hold {
                let cut = buffer.index(buffer.endIndex, offsetBy: -hold)
                output += String(buffer[..<cut])
                buffer = String(buffer[cut...])
            }
        }
        return output
    }

    /// Flush any remaining buffered text at the end of the stream.
    func flush() -> String {
        var output = ""
        consumeTags(into: &output)
        if !insideThink { output += buffer }
        buffer = ""
        return output
    }

    /// Resolve every complete tag currently buffered, appending visible text.
    private func consumeTags(into output: inout String) {
        while true {
            if insideThink {
                guard let range = buffer.range(of: Self.closeTag) else { return }
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                insideThink = false
            } else {
                guard let range = buffer.range(of: Self.openTag) else { return }
                output += String(buffer[buffer.startIndex..<range.lowerBound])
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                insideThink = true
            }
        }
    }
}
