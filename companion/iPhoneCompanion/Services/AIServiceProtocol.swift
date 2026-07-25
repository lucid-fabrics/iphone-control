import Foundation

enum StreamEvent {
    case textDelta(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case done(stopReason: String)
    case error(String)
}

/// Base protocol for all AI services — text-only streaming
protocol AIService {
    func send(messages: [APIMessage], tools: [[String: Any]], systemPrompt: String) async throws -> AsyncStream<StreamEvent>
}

/// AI service that supports tool/function calling.
/// All current services support tools, so this is a semantic marker.
/// If a service doesn't support tools, it should NOT conform to this protocol.
protocol ToolCapableAIService: AIService {
    /// Whether the service can handle tool call responses in its message format.
    var supportsToolCalling: Bool { get }
}

extension ToolCapableAIService {
    var supportsToolCalling: Bool { true }
}

/// AI service that supports vision (image inputs).
/// Services conforming to this can receive base64 images directly.
protocol VisionCapableAIService: AIService {
    /// Whether the service can process image content blocks.
    var supportsVision: Bool { get }
}

extension VisionCapableAIService {
    var supportsVision: Bool { true }
}

struct APIMessage {
    let role: String
    let content: [APIContentBlock]
}

enum APIContentBlock {
    case text(String)
    case image(base64: String, mediaType: String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: [APIContentBlock], isError: Bool)

    func toDict() -> [String: Any] {
        switch self {
        case .text(let text):
            return ["type": "text", "text": text]
        case .image(let base64, let mediaType):
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64,
                ] as [String: Any],
            ]
        case .toolUse(let id, let name, let input):
            return ["type": "tool_use", "id": id, "name": name, "input": input]
        case .toolResult(let toolUseId, let content, let isError):
            var dict: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": toolUseId,
                "content": content.map { $0.toDict() },
            ]
            if isError {
                dict["is_error"] = true
            }
            return dict
        }
    }
}
