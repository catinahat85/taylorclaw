import XCTest
@testable import TaylorClaw

final class AgentGuardTests: XCTestCase {

    // MARK: - Helpers

    private func makeGuard(
        policy: ToolPolicy = .default,
        prompter: any ApprovalPrompter = AutoApprovePrompter(),
        maxCallsPerTool: Int = 20
    ) -> (AgentGuard, AuditLog) {
        let log = AuditLog(fileURL: nil)
        let g = AgentGuard(
            policy: policy,
            prompter: prompter,
            auditLog: log,
            maxCallsPerTool: maxCallsPerTool
        )
        return (g, log)
    }

    // MARK: - Safe tools

    func testSafeToolAutoApproved() async throws {
        let (g, log) = makeGuard()
        try await g.authorize(
            toolName: "retrieve_memory",
            serverName: "mempalace",
            arguments: .object(["q": .string("x")])
        )
        let entries = await log.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .autoApproved)
        XCTAssertEqual(entries.first?.risk, .safe)
    }

    // MARK: - Cautionary tools

    func testCautionToolPromptsOnce() async throws {
        let scripted = ScriptedPrompter(
            script: ["store_memory": [.allowOnce]],
            fallback: .deny
        )
        let (g, log) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 1)
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .userApproved)
    }

    func testCautionToolSessionApprovalCachedForSubsequentCalls() async throws {
        let scripted = ScriptedPrompter(
            script: ["store_memory": [.allowForSession]],
            fallback: .deny
        )
        let (g, log) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 1, "Should only prompt once per session")
        let entries = await log.all()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].outcome, .userApproved)
        XCTAssertEqual(entries[1].outcome, .sessionApproved)
        XCTAssertEqual(entries[2].outcome, .sessionApproved)
    }

    func testCautionDeniedThrows() async {
        let (g, log) = makeGuard(prompter: AutoDenyPrompter())
        do {
            try await g.authorize(toolName: "store_memory", serverName: "mempalace")
            XCTFail("Expected denial to throw")
        } catch SafetyError.denied(let t) {
            XCTAssertEqual(t, "store_memory")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .userDenied)
    }

    // MARK: - Destructive

    func testDestructivePromptsEveryCallEvenIfPreviouslyApproved() async throws {
        let scripted = ScriptedPrompter(
            script: ["delete_memory": [.allowForSession, .allowForSession, .allowForSession]],
            fallback: .deny
        )
        let (g, _) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "delete_memory", serverName: "mempalace")
        try await g.authorize(toolName: "delete_memory", serverName: "mempalace")
        try await g.authorize(toolName: "delete_memory", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 3, "Destructive must prompt every time")
        let approved = await g.isApprovedForSession("delete_memory")
        XCTAssertFalse(approved, "Destructive must never remember approval")
    }

    // MARK: - Blocked

    func testBlockedToolNeverPrompts() async {
        let scripted = ScriptedPrompter(fallback: .allowOnce)
        let policy = ToolPolicy(blocklist: ["rm_rf"])
        let (g, log) = makeGuard(policy: policy, prompter: scripted)
        do {
            try await g.authorize(toolName: "rm_rf", serverName: "shell")
            XCTFail("Blocked tool should throw")
        } catch SafetyError.blocked {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 0, "Blocked tools must not reach the prompter")
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .blocked)
    }

    // MARK: - Loop detection

    func testLoopLimitTrips() async throws {
        let (g, log) = makeGuard(
            prompter: AutoApprovePrompter(),
            maxCallsPerTool: 3
        )
        try await g.authorize(toolName: "retrieve_memory", serverName: "mempalace")
        try await g.authorize(toolName: "retrieve_memory", serverName: "mempalace")
        try await g.authorize(toolName: "retrieve_memory", serverName: "mempalace")
        do {
            try await g.authorize(toolName: "retrieve_memory", serverName: "mempalace")
            XCTFail("Expected loop limit")
        } catch SafetyError.loopLimitExceeded(_, let limit) {
            XCTAssertEqual(limit, 3)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .loopLimit)
    }

    func testResetClearsState() async throws {
        let scripted = ScriptedPrompter(
            script: ["store_memory": [.allowForSession, .allowForSession]],
            fallback: .deny
        )
        let (g, _) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        let approvedBefore = await g.isApprovedForSession("store_memory")
        XCTAssertTrue(approvedBefore)

        await g.reset()

        let approvedAfter = await g.isApprovedForSession("store_memory")
        XCTAssertFalse(approvedAfter)
        // After reset, we should prompt again.
        try await g.authorize(toolName: "store_memory", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 2)
    }

    // MARK: - Result recording

    func testRecordResultAppendsToLog() async {
        let (g, log) = makeGuard()
        await g.recordResult(
            toolName: "retrieve_memory",
            serverName: "mempalace",
            success: true
        )
        await g.recordResult(
            toolName: "retrieve_memory",
            serverName: "mempalace",
            success: false,
            error: "timeout"
        )
        let entries = await log.all()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].outcome, .toolSuccess)
        XCTAssertEqual(entries[1].outcome, .toolError)
        XCTAssertEqual(entries[1].error, "timeout")
    }
}
