import Foundation

/// How Taylor Claw treats an outgoing message:
/// - `.chat` is the v0.1 behavior — stateless, no tools, no memory.
/// - `.agent` enables MCP tool calls, memory retrieval, and document RAG.
enum ChatMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case chat
    case agent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat: "Chat"
        case .agent: "Agent"
        }
    }
}
