import Foundation

/// Orchestrates the AI tool-calling loop: sends messages, executes tool calls, and loops.
/// Separated from Conversation to respect single-responsibility principle.
actor ToolOrchestrator {
    private let toolExecutor: ToolExecutor

    init(toolExecutor: ToolExecutor) {
        self.toolExecutor = toolExecutor
    }

    struct LoopCallbacks {
        let createService: () async -> AIService?
        let getBackend: () -> AIBackend
        let getApiMessages: () -> [APIMessage]
        let appendApiMessage: (APIMessage) -> Void
        let appendChatMessage: (ChatMessage) -> Void
        let updateChatMessage: (Int, [ContentBlock]) -> Void
        let chatMessageCount: () -> Int
        let needsVisionProxy: () -> Bool
        let describeScreenshot: (Data) async -> String
        let isCancelled: () -> Bool
    }

    // Pre-existing single-function agent loop (stream, accumulate, execute, repeat);
    // splitting it would not make the control flow clearer.
    // swiftlint:disable cyclomatic_complexity function_body_length line_length large_tuple
    func runAILoop(callbacks: LoopCallbacks) async {
        var iteration = 0

        while iteration < Constants.maxToolIterations {
            guard !callbacks.isCancelled() else { return }
            iteration += 1

            guard let service = await callbacks.createService() else {
                let backend = callbacks.getBackend()
                if backend == .claudeCode {
                    callbacks.appendChatMessage(.assistant("Error: Claude Code credentials not found or expired. Run `claude` in terminal to authenticate."))
                } else {
                    callbacks.appendChatMessage(.assistant("Error: No API key configured. Tap the model bar to add your API key."))
                }
                return
            }

            do {
                let stream = try await service.send(
                    messages: callbacks.getApiMessages(),
                    tools: ToolDefinitions.all,
                    systemPrompt: Constants.systemPrompt
                )

                var assistantText = ""
                var toolCalls: [(id: String, name: String, input: [String: Any])] = []
                var stopReason = "end_turn"
                var currentAssistantIndex: Int?

                for await event in stream {
                    guard !callbacks.isCancelled() else { return }
                    switch event {
                    case .textDelta(let delta):
                        assistantText += delta
                        if let idx = currentAssistantIndex {
                            callbacks.updateChatMessage(idx, [.text(assistantText)])
                        } else {
                            callbacks.appendChatMessage(ChatMessage(role: .assistant, content: [.text(assistantText)]))
                            currentAssistantIndex = callbacks.chatMessageCount() - 1
                        }

                    case .toolUse(let id, let name, let input):
                        toolCalls.append((id: id, name: name, input: input))

                    case .done(let reason):
                        stopReason = reason

                    case .error(let msg):
                        callbacks.appendChatMessage(.assistant("Error: \(msg)"))
                        return
                    }
                }

                // Build assistant API message with all content blocks
                var assistantBlocks: [APIContentBlock] = []
                if !assistantText.isEmpty {
                    assistantBlocks.append(.text(assistantText))
                }
                for call in toolCalls {
                    assistantBlocks.append(.toolUse(id: call.id, name: call.name, input: call.input))
                }
                if !assistantBlocks.isEmpty {
                    callbacks.appendApiMessage(APIMessage(role: "assistant", content: assistantBlocks))
                }

                // Execute whenever the model produced tool calls, regardless of how the
                // provider labeled finish_reason. OpenRouter (Bedrock) reports "end_turn"
                // even with tool_calls present, so gating on stopReason == "tool_use"
                // silently dropped valid tool calls and nothing happened.
                if toolCalls.isEmpty {
                    NSLog("[Companion] AI loop done: stopReason=%@, toolCalls=%d, textLen=%d", stopReason, toolCalls.count, assistantText.count)
                    return
                }
                NSLog("[Companion] Executing %d tool calls", toolCalls.count)

                // Execute tool calls and collect results
                var toolResultBlocks: [APIContentBlock] = []

                for call in toolCalls {
                    guard !callbacks.isCancelled() else { return }
                    // Show tool running status
                    let toolMsg = ChatMessage(role: .assistant, content: [
                        .toolCall(id: call.id, name: call.name, status: .running)
                    ])
                    callbacks.appendChatMessage(toolMsg)
                    let toolMsgIndex = callbacks.chatMessageCount() - 1

                    let result = await toolExecutor.execute(toolName: call.name, input: call.input)

                    // Update tool status
                    if result.isError {
                        callbacks.updateChatMessage(toolMsgIndex, [
                            .toolCall(id: call.id, name: call.name, status: .failed(result.text ?? "Unknown error"))
                        ])
                    } else {
                        callbacks.updateChatMessage(toolMsgIndex, [
                            .toolCall(id: call.id, name: call.name, status: .completed)
                        ])
                    }

                    // Add screenshot to chat if present
                    if let imageData = result.imageData {
                        callbacks.appendChatMessage(ChatMessage(role: .assistant, content: [.image(imageData)]))
                    }

                    // Build tool result for API
                    var resultContent: [APIContentBlock] = []
                    if let text = result.text {
                        resultContent.append(.text(text))
                    }
                    if let imageData = result.imageData {
                        if callbacks.needsVisionProxy() {
                            let description = await callbacks.describeScreenshot(imageData)
                            resultContent.append(.text("[Screenshot description]: \(description)"))
                        } else {
                            resultContent.append(.image(base64: imageData.base64EncodedString(), mediaType: "image/png"))
                        }
                    }
                    if resultContent.isEmpty {
                        resultContent.append(.text("Done"))
                    }

                    toolResultBlocks.append(.toolResult(
                        toolUseId: call.id,
                        content: resultContent,
                        isError: result.isError
                    ))
                }

                // Add tool results as a user message (Claude API requirement)
                callbacks.appendApiMessage(APIMessage(role: "user", content: toolResultBlocks))

            } catch {
                callbacks.appendChatMessage(.assistant("Error: \(error.localizedDescription)"))
                return
            }
        }

        callbacks.appendChatMessage(.assistant("Stopped: too many tool call iterations."))
    }
    // swiftlint:enable cyclomatic_complexity function_body_length line_length large_tuple
}
