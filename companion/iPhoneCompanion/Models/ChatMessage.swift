import Foundation
import AppKit

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum ContentBlock: Identifiable {
    case text(String)
    case image(Data)
    case toolCall(id: String, name: String, status: ToolStatus)

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.hashValue)"
        case .image(let d): return "img-\(d.hashValue)"
        case .toolCall(let id, _, _): return "tool-\(id)"
        }
    }
}

enum ToolStatus {
    case running
    case completed
    case failed(String)
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: [ContentBlock]
    let timestamp: Date

    init(role: MessageRole, content: [ContentBlock]) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: [.text(text)])
    }

    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: [.text(text)])
    }
}
