import Foundation

/// Abstracts the "ask the user" step of the safety flow.
///
/// The real implementation lives in Phase F and presents a SwiftUI sheet.
/// Tests and headless contexts use the stub implementations below.
protocol ApprovalPrompter: Sendable {
    func request(_ request: ApprovalRequest) async -> ApprovalDecision
}

/// Grants each request exactly once. Useful for tests where we want to
/// exercise the guard flow without blocking on UI.
struct AutoApprovePrompter: ApprovalPrompter {
    func request(_ request: ApprovalRequest) async -> ApprovalDecision { .allowOnce }
}

/// Rejects every request. Useful for verifying that a denied call surfaces
/// a `SafetyError.denied`.
struct AutoDenyPrompter: ApprovalPrompter {
    func request(_ request: ApprovalRequest) async -> ApprovalDecision { .deny }
}

/// Grants and remembers the decision for the rest of the session.
/// Useful for exercising the session-approval cache path.
struct AutoSessionApprovePrompter: ApprovalPrompter {
    func request(_ request: ApprovalRequest) async -> ApprovalDecision {
        .allowForSession
    }
}

/// Returns decisions from a supplied dictionary keyed by tool name, falling
/// back to `default` when the tool is absent.
actor ScriptedPrompter: ApprovalPrompter {
    private var script: [String: [ApprovalDecision]]
    private let defaultDecision: ApprovalDecision
    private(set) var seen: [ApprovalRequest] = []

    init(
        script: [String: [ApprovalDecision]] = [:],
        fallback: ApprovalDecision = .deny
    ) {
        self.script = script
        self.defaultDecision = fallback
    }

    func request(_ request: ApprovalRequest) async -> ApprovalDecision {
        seen.append(request)
        if var remaining = script[request.toolName], !remaining.isEmpty {
            let next = remaining.removeFirst()
            script[request.toolName] = remaining
            return next
        }
        return defaultDecision
    }
}
