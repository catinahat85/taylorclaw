import Foundation

/// Risk classification for an MCP tool.
///
/// The guard uses this to decide whether to prompt the user and whether
/// session-wide approval is offered.
enum ToolRisk: String, Codable, Sendable, Hashable {
    /// Read-only / idempotent. Auto-approved.
    case safe
    /// Mutates state but reversible. Prompt once, offer "allow for session".
    case caution
    /// Irreversible or high-impact. Prompt every call, no session memory.
    case destructive
    /// Never allowed. Surfaced to user as a blocked tool.
    case blocked
}

/// A single request for user approval of a tool call.
struct ApprovalRequest: Sendable, Hashable, Identifiable {
    let id: UUID
    let toolName: String
    let serverName: String
    let arguments: JSONValue
    let risk: ToolRisk
    let reason: String?

    init(
        id: UUID = UUID(),
        toolName: String,
        serverName: String,
        arguments: JSONValue,
        risk: ToolRisk,
        reason: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.serverName = serverName
        self.arguments = arguments
        self.risk = risk
        self.reason = reason
    }
}

/// User's response to an `ApprovalRequest`.
enum ApprovalDecision: String, Codable, Sendable, Hashable {
    /// Permit just this one call.
    case allowOnce
    /// Permit this tool for the rest of the agent session without re-asking.
    /// Ignored for `.destructive` — those always prompt.
    case allowForSession
    /// Reject this call.
    case deny
}

/// Guard failure modes.
enum SafetyError: Error, Sendable, Equatable, CustomStringConvertible {
    case blocked(tool: String)
    case denied(tool: String)
    case loopLimitExceeded(tool: String, limit: Int)

    var description: String {
        switch self {
        case .blocked(let t):            "Tool '\(t)' is blocked by policy."
        case .denied(let t):             "Tool '\(t)' was denied."
        case .loopLimitExceeded(let t, let l):
            "Tool '\(t)' exceeded the per-session call limit of \(l)."
        }
    }
}
