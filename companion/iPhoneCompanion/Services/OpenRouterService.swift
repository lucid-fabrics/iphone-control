import Foundation

class OpenRouterService: ToolCapableAIService {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func send(messages: [APIMessage], tools: [[String: Any]],
              systemPrompt: String) async throws -> AsyncStream<StreamEvent> {
        let body = buildRequestBody(messages: messages, tools: tools, systemPrompt: systemPrompt)

        guard let url = URL(string: Constants.openRouterAPIURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }

        let responseStr = String(data: data, encoding: .utf8) ?? ""
        NSLog("[Companion] OpenRouter response (%d bytes): %@", data.count, String(responseStr.prefix(500)))

        return AsyncStream { continuation in
            var gotAnyContent = false
            var toolCallAccum: [Int: SSEStreamParser.AccumulatedToolCall] = [:]

            for line in responseStr.components(separatedBy: "\n") {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))

                let result = SSEStreamParser.parseLine(
                    jsonStr,
                    toolCallAccum: &toolCallAccum,
                    continuation: continuation,
                    gotAnyContent: &gotAnyContent
                )

                switch result {
                case .done, .error:
                    continuation.finish()
                    return
                default:
                    break
                }
            }

            // Fallback: if no [DONE] and no finish_reason
            SSEStreamParser.emitToolCalls(toolCallAccum, continuation: continuation, gotContent: &gotAnyContent)

            if !gotAnyContent {
                SSEStreamParser.parseNonStreamingResponse(data: data, continuation: continuation)
            }

            continuation.finish()
        }
    }

    // Pre-existing single-pass marshalling of the whole message history into the
    // OpenAI wire format; splitting the role branches would not make it clearer.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func buildRequestBody(messages: [APIMessage], tools: [[String: Any]],
                                  systemPrompt: String) -> [String: Any] {
        var openAIMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in messages {
            if msg.role == "user" {
                var toolResultImages: [[String: Any]] = []
                let toolResults = msg.content.compactMap { block -> [String: Any]? in
                    if case .toolResult(let toolUseId, let content, _) = block {
                        var resultText = ""
                        for sub in content {
                            switch sub {
                            case .text(let text):
                                resultText += text
                            case .image(let base64, let mediaType):
                                // role:"tool" content is text-only in this format.
                                // The old code claimed "[Screenshot attached]" while
                                // attaching NOTHING, so the model drove blind. Ferry
                                // images in a follow-up user message instead.
                                toolResultImages.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:\(mediaType);base64,\(base64)"]
                                ])
                            default:
                                break
                            }
                        }
                        if resultText.isEmpty { resultText = "Done" }
                        return [
                            "role": "tool",
                            "tool_call_id": toolUseId,
                            "content": resultText
                        ]
                    }
                    return nil
                }

                if !toolResults.isEmpty {
                    openAIMessages.append(contentsOf: toolResults)
                    if !toolResultImages.isEmpty {
                        var blocks: [[String: Any]] = [
                            ["type": "text", "text": "Screenshot from the tool result above:"]
                        ]
                        blocks.append(contentsOf: toolResultImages)
                        openAIMessages.append(["role": "user", "content": blocks])
                    }
                } else {
                    var contentParts: [[String: Any]] = []
                    for block in msg.content {
                        switch block {
                        case .text(let text):
                            contentParts.append(["type": "text", "text": text])
                        case .image(let base64, let mediaType):
                            contentParts.append([
                                "type": "image_url",
                                "image_url": ["url": "data:\(mediaType);base64,\(base64)"]
                            ])
                        default:
                            break
                        }
                    }
                    if contentParts.count == 1, case .text(let soleText) = msg.content.first {
                        openAIMessages.append(["role": "user", "content": soleText])
                    } else if !contentParts.isEmpty {
                        openAIMessages.append(["role": "user", "content": contentParts])
                    }
                }
            } else if msg.role == "assistant" {
                var assistantMsg: [String: Any] = ["role": "assistant"]
                var textContent = ""
                var toolCallsList: [[String: Any]] = []

                for block in msg.content {
                    switch block {
                    case .text(let text):
                        textContent += text
                    case .toolUse(let id, let name, let input):
                        let argsData = try? JSONSerialization.data(withJSONObject: input)
                        let argsStr = argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCallsList.append([
                            "id": id,
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": argsStr
                            ] as [String: Any]
                        ])
                    default:
                        break
                    }
                }

                if !textContent.isEmpty {
                    assistantMsg["content"] = textContent
                }
                if !toolCallsList.isEmpty {
                    assistantMsg["tool_calls"] = toolCallsList
                }
                openAIMessages.append(assistantMsg)
            }
        }

        let openAITools = tools.compactMap { tool -> [String: Any]? in
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
                ] as [String: Any]
            ]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": Constants.maxTokens,
            "stream": true,
            "messages": openAIMessages
        ]

        if !openAITools.isEmpty {
            body["tools"] = openAITools
        }

        return body
    }
}
