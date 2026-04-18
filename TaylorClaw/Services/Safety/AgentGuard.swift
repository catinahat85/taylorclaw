import Foundation

/// Central safety gate for agent-mode tool calls.
///
/// Every MCP tool invocation in Phase F flows through `authorize(...)`.
/// The guard:
///   1. Enforces a per-session call limit per tool (loop detection).
///   2. Looks up the tool's `ToolRisk` via `ToolPolicy`.
///   3. For `.blocked` tools, refuses without prompting.
///   4. For `.safe` tools, auto-approves.
///   5. For `.caution`, prompts once and remembers "allow for session".
///   6. For `.destructive`, prompts every time and never remembers.
/// Every decision is written to `AuditLog`. Call `recordResult(...)` after
/// the tool runs to append a success/error entry.
actor AgentGuard {
    let policy: ToolPolicy
    let prompter: any ApprovalPrompter
    let auditLog: AuditLog
    let maxCallsPerTool: Int

    private var sessionApprovals: Set<String> = []
    private var callCounts: [String: Int] = [:]

    init(
        policy: ToolPolicy = .default,
        prompter: any ApprovalPrompter,
        auditLog: AuditLog = .shared,
        maxCallsPerTool: Int = 20
    ) {
        self.policy = policy
        self.prompter = prompter
        self.auditLog = auditLog
        self.maxCallsPerTool = maxCallsPerTool
    }

    /// Ask the guard whether a pending tool call may proceed.
    ///
    /// Throws `SafetyError` when the call is blocked, denied, or would
    /// trip the loop limit. Returns normally when the call is approved —
    /// the caller is then responsible for executing the tool and calling
    /// `recordResult(...)` with the outcome.
    func authorize(
        toolName: String,
        serverName: String,
        arguments: JSONValue = .object([:]),
        reason: String? = nil
    ) async throws {
        let nextCount = (callCounts[toolName] ?? 0) + 1
        if nextCount > maxCallsPerTool {
            await auditLog.append(AuditEntry(
                toolName: toolName,
                serverName: serverName,
                risk: policy.risk(for: toolName),
                outcome: .loopLimit,
                arguments: arguments
            ))
            throw SafetyError.loopLimitExceeded(tool: toolName, limit: maxCallsPerTool)
        }
        callCounts[toolName] = nextCount

        let risk = policy.risk(for: toolName)
        switch risk {
        case .blocked:
            await auditLog.append(AuditEntry(
                toolName: toolName,
                serverName: serverName,
                risk: .blocked,
                outcome: .blocked,
                arguments: arguments
            ))
            throw SafetyError.blocked(tool: toolName)

        case .safe:
            await auditLog.append(AuditEntry(
                toolName: toolName,
                serverName: serverName,
                risk: .safe,
                outcome: .autoApproved,
                arguments: arguments
            ))

        case .caution:
            if sessionApprovals.contains(toolName) {
                await auditLog.append(AuditEntry(
                    toolName: toolName,
                    serverName: serverName,
                    risk: .caution,
                    outcome: .sessionApproved,
                    arguments: arguments
                ))
                return
            }
            let req = ApprovalRequest(
                toolName: toolName, serverName: serverName,
                arguments: arguments, risk: .caution, reason: reason
            )
            let decision = await prompter.request(req)
            try await handle(decision: decision, request: req, rememberAllowed: true)

        case .destructive:
            let req = ApprovalRequest(
                toolName: toolName, serverName: serverName,
                arguments: arguments, risk: .destructive, reason: reason
            )
            let decision = await prompter.request(req)
            // Destructive calls never remember — ignore allowForSession.
            try await handle(decision: decision, request: req, rememberAllowed: false)
        }
    }

    /// Record a tool's post-execution outcome.
    func recordResult(
        toolName: String,
        serverName: String,
        risk: ToolRisk? = nil,
        success: Bool,
        error: String? = nil
    ) async {
        await auditLog.append(AuditEntry(
            toolName: toolName,
            serverName: serverName,
            risk: risk ?? policy.risk(for: toolName),
            outcome: success ? .toolSuccess : .toolError,
            error: error
        ))
    }

    /// Reset per-session state. Called when the user starts a new agent
    /// conversation or explicitly clears approvals.
    func reset() {
        sessionApprovals.removeAll()
        callCounts.removeAll()
    }

    // MARK: - Introspection (mostly for tests / debug UI)

    func isApprovedForSession(_ toolName: String) -> Bool {
        sessionApprovals.contains(toolName)
    }

    func callCount(for toolName: String) -> Int {
        callCounts[toolName] ?? 0
    }

    // MARK: - Private

    private func handle(
        decision: ApprovalDecision,
        request: ApprovalRequest,
        rememberAllowed: Bool
    ) async throws {
        switch decision {
        case .deny:
            await auditLog.append(AuditEntry(
                toolName: request.toolName,
                serverName: request.serverName,
                risk: request.risk,
                outcome: .userDenied,
                arguments: request.arguments
            ))
            throw SafetyError.denied(tool: request.toolName)

        case .allowOnce:
            await auditLog.append(AuditEntry(
                toolName: request.toolName,
                serverName: request.serverName,
                risk: request.risk,
                outcome: .userApproved,
                arguments: request.arguments
            ))

        case .allowForSession:
            if rememberAllowed {
                sessionApprovals.insert(request.toolName)
            }
            await auditLog.append(AuditEntry(
                toolName: request.toolName,
                serverName: request.serverName,
                risk: request.risk,
                outcome: .userApproved,
                arguments: request.arguments
            ))
        }
    }
}
