import Foundation

/// Reusable SSE line parser and tool call accumulator for OpenAI-compatible streaming APIs.
enum SSEStreamParser {
    struct AccumulatedToolCall {
        var id: String = ""
        var name: String = ""
        var args: String = ""
    }

    /// Parse a single SSE data line (after stripping "data: " prefix) and accumulate tool calls.
    /// Returns the parsed content or nil if the line should be skipped.
    static func parseLine(
        _ jsonStr: String,
        toolCallAccum: inout [Int: AccumulatedToolCall],
        continuation: AsyncStream<StreamEvent>.Continuation,
        gotAnyContent: inout Bool
    ) -> ParseResult {
        if jsonStr == "[DONE]" {
            emitToolCalls(toolCallAccum, continuation: continuation, gotContent: &gotAnyContent)
            if !gotAnyContent {
                continuation.yield(.error("No response from model"))
            }
            continuation.yield(.done(stopReason: "end_turn"))
            return .done
        }

        guard let jsonData = jsonStr.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return .skip }

        if let error = event["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "Unknown API error"
            continuation.yield(.error(msg))
            return .error
        }

        guard let choices = event["choices"] as? [[String: Any]],
              let choice = choices.first
        else { return .skip }

        let finishReason = choice["finish_reason"] as? String

        if let delta = choice["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                gotAnyContent = true
                continuation.yield(.textDelta(content))
            }

            // Accumulate tool call chunks
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let index = call["index"] as? Int ?? 0
                    var existing = toolCallAccum[index] ?? AccumulatedToolCall()

                    if let id = call["id"] as? String, !id.isEmpty {
                        existing.id = id
                    }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            existing.name = name
                        }
                        if let args = function["arguments"] as? String {
                            existing.args += args
                        }
                    }
                    toolCallAccum[index] = existing
                }
            }
        }

        if let reason = finishReason {
            emitToolCalls(toolCallAccum, continuation: continuation, gotContent: &gotAnyContent)
            toolCallAccum.removeAll()

            let stopReason = (reason == "tool_calls") ? "tool_use" : "end_turn"
            continuation.yield(.done(stopReason: stopReason))
            return .finishReason(reason)
        }

        return .continue
    }

    /// Emit accumulated tool calls as StreamEvents.
    static func emitToolCalls(
        _ accum: [Int: AccumulatedToolCall],
        continuation: AsyncStream<StreamEvent>.Continuation,
        gotContent: inout Bool
    ) {
        for index in accum.keys.sorted() {
            let call = accum[index]
            guard let call, !call.name.isEmpty else { continue }
            gotContent = true

            let id = call.id.isEmpty ? "or-\(UUID().uuidString.prefix(8))" : call.id
            var input: [String: Any] = [:]
            if let argsData = call.args.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                input = parsed
            }
            continuation.yield(.toolUse(id: id, name: call.name, input: input))
        }
    }

    /// Parse a non-streaming JSON response and emit events.
    static func parseNonStreamingResponse(
        data: Data,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            continuation.yield(.error("Empty response from model"))
            return
        }

        if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "Unknown error"
            continuation.yield(.error(msg))
            return
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any]
        else {
            continuation.yield(.error("Unexpected response format"))
            return
        }

        if let content = message["content"] as? String {
            continuation.yield(.textDelta(content))
        }

        // Check for tool calls in non-streaming response
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String
                else { continue }
                let id = call["id"] as? String ?? "or-\(UUID().uuidString.prefix(8))"
                let argsStr = function["arguments"] as? String ?? "{}"
                var input: [String: Any] = [:]
                if let argsData = argsStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                    input = parsed
                }
                continuation.yield(.toolUse(id: id, name: name, input: input))
            }
            let fr = choice["finish_reason"] as? String
            let sr = (fr == "tool_calls") ? "tool_use" : "end_turn"
            continuation.yield(.done(stopReason: sr))
        } else {
            continuation.yield(.done(stopReason: "end_turn"))
        }
    }

    enum ParseResult {
        case done
        case error
        case skip
        case `continue`
        case finishReason(String)
    }
}
